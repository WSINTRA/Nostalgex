package app.nostalgex.backend.jellyfin

import app.nostalgex.backend.DeviceCapabilities
import app.nostalgex.backend.LoadProgress
import app.nostalgex.backend.StreamPlan
import app.nostalgex.backend.MediaBackend
import app.nostalgex.model.MediaItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException

/** [MediaBackend] for Jellyfin. Collaborators are injected so tests can swap the client and mapper. */
class JellyfinBackend(
    private val client: OkHttpClient,
    private val session: JellyfinSession,
    private val deviceId: String,
    private val deviceName: String = "Fire TV",
    private val mapper: JellyfinItemMapper = JellyfinItemMapper(),
    private val capabilities: DeviceCapabilities = DeviceCapabilities(hevc = false),
    private val pageSize: Int = 200,
    private val showBatchSize: Int = 10,
) : MediaBackend {
    private val json = Json { ignoreUnknownKeys = true }

    override val serverId: String get() = session.serverId.ifEmpty { session.baseUrl }

    override val authHeaders: Map<String, String>
        get() = mapOf("Authorization" to JellyfinAuthClient.authorizationHeader(deviceId, deviceName, session.accessToken))

    @Serializable private data class InfoDto(val ServerName: String? = null)

    override suspend fun testConnection(): String =
        json.decodeFromString(InfoDto.serializer(), get("/System/Info")).ServerName ?: session.serverName

    override suspend fun loadLibrary(onProgress: (LoadProgress) -> Unit): List<MediaItem> {
        val sections = views()
        val all = ArrayList<MediaItem>()
        sections.forEachIndexed { i, section ->
            onProgress(LoadProgress(i, sections.size, section.Name ?: "Library", all.size))
            all += when (section.CollectionType?.lowercase()) {
                "tvshows" -> showsSection(section.Id)
                "musicvideos" -> movieSection(section.Id, music = true)
                else -> movieSection(section.Id, music = false)
            }
        }
        return all
    }

    private val planner = JellyfinStreamPlanner(session.baseUrl, session.accessToken, deviceId, capabilities)

    override fun streamPlan(item: MediaItem, offsetSeconds: Long, forceTranscode: Boolean): StreamPlan =
        planner.plan(item, offsetSeconds, forceTranscode)

    override fun thumbnailUrl(item: MediaItem, width: Int): String? {
        val b = "${session.baseUrl}/Items/${item.id}/Images/Primary".toHttpUrl().newBuilder().addQueryParameter("maxWidth", width.toString())
        item.thumbTag?.let { b.addQueryParameter("tag", it) }
        return b.build().toString()
    }

    private suspend fun views(): List<JellyfinItemDto> =
        json.decodeFromString(ItemsResponseDto.serializer(), get("/UserViews", "userId" to session.userId)).Items.orEmpty()

    private suspend fun movieSection(parentId: String, music: Boolean) =
        fetchAll(parentId, "Movie").mapNotNull { mapper.movie(it, music) }

    /** Lists series, then fetches each series' episodes in small concurrent batches. */
    private suspend fun showsSection(parentId: String): List<MediaItem> {
        val series = fetchAll(parentId, "Series")
        val out = ArrayList<MediaItem>()
        for (batch in series.chunked(showBatchSize)) {
            out += coroutineScope { batch.map { show -> async { episodes(show) } }.awaitAll() }.flatten()
        }
        return out
    }

    private suspend fun episodes(show: JellyfinItemDto): List<MediaItem> =
        try { fetchAll(show.Id, "Episode").mapNotNull { mapper.episode(it, show) } }
        catch (e: IOException) { emptyList() } // skip a show that fails, like tvOS
        catch (e: SignInError.ServerError) { emptyList() }

    private suspend fun fetchAll(parentId: String, types: String): List<JellyfinItemDto> {
        val collected = ArrayList<JellyfinItemDto>()
        var start = 0
        while (true) {
            val page = json.decodeFromString(
                ItemsResponseDto.serializer(),
                get(
                    "/Items",
                    "userId" to session.userId, "ParentId" to parentId, "Recursive" to "true",
                    "IncludeItemTypes" to types,
                    "Fields" to "Overview,Genres,Studios,MediaSources,ProductionYear,PremiereDate,DateCreated",
                    "StartIndex" to start.toString(), "Limit" to pageSize.toString(), "SortBy" to "SortName",
                ),
            )
            val items = page.Items.orEmpty()
            collected += items
            start += items.size
            if (items.isEmpty() || collected.size >= (page.TotalRecordCount ?: collected.size)) return collected
        }
    }

    private suspend fun get(path: String, vararg query: Pair<String, String>): String = withContext(Dispatchers.IO) {
        val url = (session.baseUrl + path).toHttpUrl().newBuilder().apply { query.forEach { (k, v) -> addQueryParameter(k, v) } }.build()
        val req = Request.Builder().url(url).header("Accept", "application/json").headers(okhttp3.Headers.headersOf(*authHeaders.flatMap { listOf(it.key, it.value) }.toTypedArray())).build()
        client.newCall(req).execute().use { resp ->
            when {
                resp.code == 401 || resp.code == 403 -> throw SignInError.BadCredentials()
                !resp.isSuccessful -> throw SignInError.ServerError(resp.code)
                else -> resp.body?.string().orEmpty()
            }
        }
    }
}
