package app.nostalgex.store

import app.nostalgex.backend.jellyfin.JellyfinSession
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Remembers the signed-in Jellyfin session so a relaunch skips the connect screen. */
class SessionStore(private val kv: KeyValueStore) {
    @Serializable
    private data class Dto(val baseUrl: String, val accessToken: String, val userId: String, val serverId: String, val serverName: String)

    fun save(s: JellyfinSession) {
        kv.put(KEY, Json.encodeToString(Dto.serializer(), Dto(s.baseUrl, s.accessToken, s.userId, s.serverId, s.serverName)))
    }

    fun load(): JellyfinSession? {
        val raw = kv.get(KEY) ?: return null
        return try {
            Json.decodeFromString(Dto.serializer(), raw).let { JellyfinSession(it.baseUrl, it.accessToken, it.userId, it.serverId, it.serverName) }
        } catch (e: Exception) { null }
    }

    fun clear() = kv.remove(KEY)

    private companion object { const val KEY = "session" }
}

/** A stable per-install id sent to the server as DeviceId. [newId] is injected for tests. */
class DeviceIdProvider(
    private val kv: KeyValueStore,
    private val newId: () -> String = { java.util.UUID.randomUUID().toString() },
) {
    fun get(): String = kv.get(KEY) ?: newId().also { kv.put(KEY, it) }
    private companion object { const val KEY = "device_id" }
}
