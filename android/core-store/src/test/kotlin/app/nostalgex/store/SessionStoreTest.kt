package app.nostalgex.store

import app.nostalgex.backend.jellyfin.JellyfinSession
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class SessionStoreTest {
    private val session = JellyfinSession("http://h:8096", "tok", "u1", "srv", "Home")

    @Test fun `empty store has no session`() = assertNull(SessionStore(InMemoryKeyValueStore()).load())

    @Test fun `save then load round trips`() {
        val kv = InMemoryKeyValueStore()
        SessionStore(kv).save(session)
        assertEquals(session, SessionStore(kv).load())
    }

    @Test fun `clear forgets the session`() {
        val store = SessionStore(InMemoryKeyValueStore())
        store.save(session); store.clear()
        assertNull(store.load())
    }

    @Test fun `corrupt stored value reads as no session`() {
        val kv = InMemoryKeyValueStore().apply { put("session", "{nope") }
        assertNull(SessionStore(kv).load())
    }

    @Test fun `device id is generated once and then stable`() {
        val kv = InMemoryKeyValueStore()
        var n = 0
        val first = DeviceIdProvider(kv) { "id-${++n}" }.get()
        val second = DeviceIdProvider(kv) { "id-${++n}" }.get()
        assertEquals("id-1", first); assertEquals(first, second)
        assertNotEquals("id-2", second)
    }
}
