package app.nostalgex.store

import app.nostalgex.backend.jellyfin.JellyfinSession
import kotlin.test.Test
import kotlin.test.assertEquals

class StartupRouterTest {
    private val session = JellyfinSession("http://h:8096", "tok", "u", "srv", "Home")

    @Test fun `no saved session goes to connect`() =
        assertEquals(AppRoute.Connect, StartupRouter(SessionStore(InMemoryKeyValueStore())).initialRoute())

    @Test fun `saved session goes straight to loading`() {
        val store = SessionStore(InMemoryKeyValueStore()).apply { save(session) }
        assertEquals(AppRoute.LoadLibrary(session), StartupRouter(store).initialRoute())
    }

    @Test fun `sign out clears the session and returns to connect`() {
        val store = SessionStore(InMemoryKeyValueStore()).apply { save(session) }
        assertEquals(AppRoute.Connect, StartupRouter(store).signOut())
        assertEquals(AppRoute.Connect, StartupRouter(store).initialRoute())
    }
}
