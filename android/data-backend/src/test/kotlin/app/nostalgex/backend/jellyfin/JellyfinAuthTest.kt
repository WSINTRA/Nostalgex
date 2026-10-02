package app.nostalgex.backend.jellyfin

import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class JellyfinAuthTest {
    private val server = MockWebServer().also { it.start() }
    private val base = server.url("/").toString().trimEnd('/')
    private val client = OkHttpClient.Builder().callTimeout(2, TimeUnit.SECONDS).build()
    private val auth = JellyfinAuthClient(client, deviceId = "dev-1")

    @AfterTest fun tearDown() = server.shutdown()

    private val okBody = """{"AccessToken":"tok","User":{"Id":"u1","ServerName":"Home"},"ServerId":"srv"}"""

    @Test fun `successful sign in returns session`() = runTest {
        server.enqueue(MockResponse().setBody(okBody))
        val s = auth.signIn(base, "bob", "pw")
        assertEquals("tok", s.accessToken); assertEquals("u1", s.userId)
        assertEquals("srv", s.serverId); assertEquals("Home", s.serverName); assertEquals(base, s.baseUrl)
    }

    @Test fun `request is a POST with MediaBrowser header and credentials`() = runTest {
        server.enqueue(MockResponse().setBody(okBody))
        auth.signIn(base, "bob", "pw")
        val req = server.takeRequest()
        assertEquals("POST", req.method)
        assertEquals("/Users/AuthenticateByName", req.path)
        val h = req.getHeader("Authorization")!!
        assertTrue(h.startsWith("MediaBrowser ") && "DeviceId=\"dev-1\"" in h && "Token=" !in h, h)
        assertTrue("\"Username\":\"bob\"" in req.body.readUtf8())
    }

    @Test fun `401 is bad credentials`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        assertIs<SignInError.BadCredentials>(runCatching { auth.signIn(base, "a", "b") }.exceptionOrNull())
    }

    @Test fun `html reply means wrong path or proxy page`() = runTest {
        server.enqueue(MockResponse().setBody("  <!doctype html><html>"))
        assertIs<SignInError.NotJellyfin>(runCatching { auth.signIn(base, "a", "b") }.exceptionOrNull())
    }

    @Test fun `server error is reported with its code`() = runTest {
        server.enqueue(MockResponse().setResponseCode(500))
        val e = runCatching { auth.signIn(base, "a", "b") }.exceptionOrNull()
        assertEquals(500, assertIs<SignInError.ServerError>(e).code)
    }

    @Test fun `missing token is bad credentials`() = runTest {
        server.enqueue(MockResponse().setBody("""{"User":{"Id":"u"}}"""))
        assertIs<SignInError.BadCredentials>(runCatching { auth.signIn(base, "a", "b") }.exceptionOrNull())
    }

    @Test fun `timeout is classified`() = runTest {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        assertIs<SignInError.Timeout>(runCatching { auth.signIn(base, "a", "b") }.exceptionOrNull())
    }

    @Test fun `refused connection is wrong port`() = runTest {
        val dead = base
        server.shutdown()
        assertIs<SignInError.ConnectionRefused>(runCatching { auth.signIn(dead, "a", "b") }.exceptionOrNull())
    }

    @Test fun `unknown host is classified`() = runTest {
        assertIs<SignInError.UnknownHost>(runCatching { auth.signIn("http://no-such-host.invalid:8096", "a", "b") }.exceptionOrNull())
    }

    @Test fun `tries candidates in order until one answers`() = runTest {
        val dead = "http://127.0.0.1:1"
        server.enqueue(MockResponse().setBody(okBody))
        val s = auth.signInFirstReachable(listOf(dead, base), "a", "b")
        assertEquals(base, s.baseUrl)
    }

    @Test fun `bad credentials stop the candidate search`() = runTest {
        server.enqueue(MockResponse().setResponseCode(401))
        assertIs<SignInError.BadCredentials>(runCatching { auth.signInFirstReachable(listOf(base, "http://127.0.0.1:1"), "a", "b") }.exceptionOrNull())
    }
}
