package app.nostalgex.presentation

import app.nostalgex.backend.jellyfin.JellyfinSession
import app.nostalgex.backend.jellyfin.SignInError
import app.nostalgex.store.InMemoryKeyValueStore
import app.nostalgex.store.SessionStore
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConnectModelTest {
    private val session = JellyfinSession("http://h:8096", "tok", "u", "srv", "Home")
    private val sessions = SessionStore(InMemoryKeyValueStore())
    private var calls = mutableListOf<List<String>>()
    private var result: () -> JellyfinSession = { session }

    private val service = SignInService { candidates, _, _ -> calls += candidates; result() }
    private fun model() = ConnectModel(service, sessions)

    private fun ConnectModel.fill(server: String = "192.168.1.5", user: String = "bob", pw: String = "pw") {
        setServer(server); setUsername(user); setPassword(pw)
    }

    @Test fun `starts idle and empty`() {
        val s = model().state.value
        assertEquals(ConnectStatus.Idle, s.status); assertEquals("", s.server)
    }

    @Test fun `cannot submit until server and username are filled`() {
        val m = model()
        assertTrue(!m.state.value.canSubmit)
        m.setServer("h"); assertTrue(!m.state.value.canSubmit)
        m.setUsername("bob"); assertTrue(m.state.value.canSubmit) // empty password is allowed by Jellyfin
    }

    @Test fun `submit normalizes the address into candidates`() = runTest {
        val m = model().apply { fill("192.168.1.5") }
        m.submit()
        assertEquals(listOf(listOf("http://192.168.1.5:8096", "http://192.168.1.5")), calls)
    }

    @Test fun `success saves the session and reports it`() = runTest {
        val m = model().apply { fill() }
        m.submit()
        assertEquals(ConnectStatus.Connected(session), m.state.value.status)
        assertEquals(session, sessions.load())
    }

    @Test fun `failure shows a specific message and saves nothing`() = runTest {
        val cases = mapOf<SignInError, String>(
            SignInError.BadCredentials() to "username or password",
            SignInError.UnknownHost() to "address",
            SignInError.ConnectionRefused() to "port",
            SignInError.Timeout() to "reach",
            SignInError.Certificate() to "certificate",
            SignInError.NotJellyfin() to "Jellyfin",
            SignInError.ServerError(503) to "503",
        )
        for ((error, hint) in cases) {
            result = { throw error }
            val m = model().apply { fill() }
            m.submit()
            val status = assertIs<ConnectStatus.Failed>(m.state.value.status)
            assertTrue(status.message.contains(hint, ignoreCase = true), "${error::class.simpleName}: ${status.message}")
        }
        assertNull(sessions.load())
    }

    @Test fun `editing after a failure clears the error`() = runTest {
        result = { throw SignInError.BadCredentials() }
        val m = model().apply { fill() }
        m.submit()
        m.setPassword("other")
        assertEquals(ConnectStatus.Idle, m.state.value.status)
    }

    @Test fun `unusable address fails without calling the server`() = runTest {
        val m = model().apply { fill(server = "http://") }
        m.submit()
        assertIs<ConnectStatus.Failed>(m.state.value.status)
        assertTrue(calls.isEmpty())
    }

    @Test fun `unexpected exceptions become a generic failure`() = runTest {
        result = { throw IllegalStateException("boom") }
        val m = model().apply { fill() }
        m.submit()
        assertIs<ConnectStatus.Failed>(m.state.value.status)
    }
}
