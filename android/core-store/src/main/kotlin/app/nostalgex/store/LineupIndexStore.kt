package app.nostalgex.store

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest

/**
 * Which item ids each channel's base pool holds, so launches skip re-filtering the whole library.
 * [key] captures everything the result depends on; a different key means the index is stale.
 */
@Serializable
data class LineupIndex(val key: String, val channelItemIds: Map<Int, List<String>>)

interface LineupIndexStore {
    fun load(serverId: String): LineupIndex?
    fun save(serverId: String, index: LineupIndex)
}

class FileLineupIndexStore(private val dir: File) : LineupIndexStore {
    private val json = Json { ignoreUnknownKeys = true }

    override fun load(serverId: String): LineupIndex? {
        val f = file(serverId)
        if (!f.exists()) return null
        return try { json.decodeFromString(LineupIndex.serializer(), f.readText()) } catch (e: Exception) { null }
    }

    override fun save(serverId: String, index: LineupIndex) =
        atomicWrite(file(serverId), json.encodeToString(LineupIndex.serializer(), index))

    private fun file(serverId: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(serverId.toByteArray()).joinToString("") { "%02x".format(it) }.take(24)
        return File(dir, "lineup_$hash.json")
    }
}

class InMemoryLineupIndexStore : LineupIndexStore {
    private val map = HashMap<String, LineupIndex>()
    override fun load(serverId: String) = map[serverId]
    override fun save(serverId: String, index: LineupIndex) { map[serverId] = index }
}
