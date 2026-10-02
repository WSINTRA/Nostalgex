package app.nostalgex.store

import app.nostalgex.model.MediaItem
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest

@Serializable
data class LibrarySnapshot(val serverId: String, val savedAtEpochSec: Long, val items: List<MediaItem>)

/** Caches the scanned library so launches do not rescan (tvOS: LibrarySnapshotStore). */
interface LibrarySnapshotStore {
    fun load(serverId: String): LibrarySnapshot?
    fun save(snapshot: LibrarySnapshot)
    fun clear(serverId: String)
}

class FileLibrarySnapshotStore(private val dir: File) : LibrarySnapshotStore {
    private val json = Json { ignoreUnknownKeys = true }

    override fun load(serverId: String): LibrarySnapshot? {
        val f = file(serverId)
        if (!f.exists()) return null
        return try { json.decodeFromString(LibrarySnapshot.serializer(), f.readText()) } catch (e: Exception) { null }
    }

    override fun save(snapshot: LibrarySnapshot) =
        atomicWrite(file(snapshot.serverId), json.encodeToString(LibrarySnapshot.serializer(), snapshot))

    override fun clear(serverId: String) { file(serverId).delete() }

    /** Hashed so any server id (URLs included) is a safe file name. */
    private fun file(serverId: String): File {
        val hash = MessageDigest.getInstance("SHA-256").digest(serverId.toByteArray()).joinToString("") { "%02x".format(it) }.take(24)
        return File(dir, "library_$hash.json")
    }
}

class InMemoryLibrarySnapshotStore : LibrarySnapshotStore {
    private val map = HashMap<String, LibrarySnapshot>()
    override fun load(serverId: String) = map[serverId]
    override fun save(snapshot: LibrarySnapshot) { map[snapshot.serverId] = snapshot }
    override fun clear(serverId: String) { map.remove(serverId) }
}
