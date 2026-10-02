package app.nostalgex.backend.jellyfin

import app.nostalgex.backend.LoadProgress
import app.nostalgex.model.MediaType
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class JellyfinBackendTest {
    private val requests = mutableListOf<RecordedRequest>()
    private val routes = HashMap<String, (RecordedRequest) -> MockResponse>()
    private val server = MockWebServer().also {
        it.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                requests += request
                val path = request.requestUrl!!.encodedPath
                return routes[path]?.invoke(request) ?: MockResponse().setResponseCode(404)
            }
        }
        it.start()
    }
    private val session get() = JellyfinSession(server.url("/").toString().trimEnd('/'), "tok", "user1", "srv", "Home")
    private fun backend(pageSize: Int = 200) = JellyfinBackend(OkHttpClient(), session, deviceId = "d", pageSize = pageSize)
    private val tick = 600_000_000L

    @AfterTest fun tearDown() = server.shutdown()

    private fun movieJson(id: String, name: String) =
        """{"Id":"$id","Name":"$name","RunTimeTicks":${90 * tick},"Genres":["Drama"],"MediaSources":[{"Id":"s$id","Container":"mp4"}]}"""

    private fun views(vararg v: Pair<String, String?>) = routes.put("/UserViews") {
        MockResponse().setBody("""{"Items":[${v.joinToString(",") { """{"Id":"${it.first}","Name":"L${it.first}","CollectionType":${it.second?.let { c -> "\"$c\"" }}}""" }}]}""")
    }

    @Test fun `testConnection returns server name and sends token`() = runTest {
        routes["/System/Info"] = { MockResponse().setBody("""{"ServerName":"Basement"}""") }
        assertEquals("Basement", backend().testConnection())
        assertTrue("Token=\"tok\"" in requests.single().getHeader("Authorization")!!)
    }

    @Test fun `testConnection 401 is bad credentials`() = runTest {
        routes["/System/Info"] = { MockResponse().setResponseCode(401) }
        assertIs<SignInError.BadCredentials>(runCatching { backend().testConnection() }.exceptionOrNull())
    }

    @Test fun `movie library pages until total is reached`() = runTest {
        views("v1" to "movies")
        routes["/Items"] = { r ->
            val start = r.requestUrl!!.queryParameter("StartIndex")!!.toInt()
            val all = listOf("a", "b", "c")
            val page = all.drop(start).take(2)
            MockResponse().setBody("""{"TotalRecordCount":3,"Items":[${page.joinToString(",") { movieJson(it, it.uppercase()) }}]}""")
        }
        val items = backend(pageSize = 2).loadLibrary()
        assertEquals(listOf("A", "B", "C"), items.map { it.title })
        val itemReqs = requests.filter { it.requestUrl!!.encodedPath == "/Items" }
        assertEquals(listOf("0", "2"), itemReqs.map { it.requestUrl!!.queryParameter("StartIndex") })
        val q = itemReqs.first().requestUrl!!
        assertEquals("v1", q.queryParameter("ParentId")); assertEquals("Movie", q.queryParameter("IncludeItemTypes"))
        assertEquals("user1", q.queryParameter("userId")); assertEquals("true", q.queryParameter("Recursive"))
    }

    @Test fun `tv library fetches series then episodes`() = runTest {
        views("tv" to "tvshows")
        routes["/Items"] = { r ->
            val u = r.requestUrl!!
            when (u.queryParameter("IncludeItemTypes")) {
                "Series" -> MockResponse().setBody("""{"TotalRecordCount":1,"Items":[{"Id":"sh","Name":"Show","Genres":["Comedy"]}]}""")
                else -> {
                    assertEquals("sh", u.queryParameter("ParentId"))
                    MockResponse().setBody("""{"TotalRecordCount":2,"Items":[
                        {"Id":"e1","Name":"One","RunTimeTicks":${22 * tick},"ParentIndexNumber":1,"IndexNumber":1},
                        {"Id":"e2","Name":"Zero","RunTimeTicks":0}]}""")
                }
            }
        }
        val items = backend().loadLibrary()
        assertEquals(1, items.size)
        assertEquals(MediaType.EPISODE, items.single().type)
        assertEquals("Show", items.single().title)
    }

    @Test fun `music video library is tagged`() = runTest {
        views("mv" to "musicvideos")
        routes["/Items"] = { MockResponse().setBody("""{"TotalRecordCount":1,"Items":[${movieJson("x", "Artist - Song")}]}""") }
        assertEquals("MUSIC_VIDEO", backend().loadLibrary().single().librarySource.toString())
    }

    @Test fun `progress is reported per section`() = runTest {
        views("a" to "movies", "b" to "movies")
        routes["/Items"] = { MockResponse().setBody("""{"TotalRecordCount":1,"Items":[${movieJson("x", "X")}]}""") }
        val seen = mutableListOf<LoadProgress>()
        backend().loadLibrary { seen += it }
        assertEquals(listOf(0, 1), seen.map { it.sectionIndex })
        assertEquals(listOf(0, 1), seen.map { it.itemsLoadedSoFar })
        assertEquals(2, seen.first().totalSections)
    }

    @Test fun `a show that fails is skipped, not fatal`() = runTest {
        views("tv" to "tvshows")
        routes["/Items"] = { r ->
            if (r.requestUrl!!.queryParameter("IncludeItemTypes") == "Series")
                MockResponse().setBody("""{"TotalRecordCount":2,"Items":[{"Id":"bad","Name":"Bad"},{"Id":"ok","Name":"Ok"}]}""")
            else if (r.requestUrl!!.queryParameter("ParentId") == "bad") MockResponse().setResponseCode(500)
            else MockResponse().setBody("""{"TotalRecordCount":1,"Items":[{"Id":"e","RunTimeTicks":${20 * tick}}]}""")
        }
        assertEquals(listOf("Ok"), backend().loadLibrary().map { it.title })
    }

    @Test fun `section failure propagates`() = runTest {
        views("v" to "movies")
        routes["/Items"] = { MockResponse().setResponseCode(500) }
        assertIs<SignInError.ServerError>(runCatching { backend().loadLibrary() }.exceptionOrNull())
    }

    @Test fun `thumbnail url uses image tag and width`() {
        val item = app.nostalgex.model.MediaItem("m1", "T", 90, MediaType.MOVIE, thumbTag = "abc")
        assertEquals("${session.baseUrl}/Items/m1/Images/Primary?maxWidth=300&tag=abc", backend().thumbnailUrl(item, 300))
    }

    @Test fun `auth headers carry the token`() {
        assertTrue("Token=\"tok\"" in backend().authHeaders.getValue("Authorization"))
        assertEquals("srv", backend().serverId)
    }
}
