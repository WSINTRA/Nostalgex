package app.nostalgex.backend

import app.nostalgex.model.MediaItem

/** Progress of a library scan. */
data class LoadProgress(val sectionIndex: Int, val totalSections: Int, val sectionTitle: String, val itemsLoadedSoFar: Int)

/**
 * A media server the app can tune into (tvOS: `MediaBackend`). Everything downstream
 * (filter, schedule, player) sees only [MediaItem], so adding Plex or Emby later means
 * implementing this interface and nothing else.
 */
interface MediaBackend {
    /** Stable identifier of the server; routes playback and images back to it. */
    val serverId: String

    /** Headers carrying auth, applied by the player when fetching media. */
    val authHeaders: Map<String, String>

    /** Verifies connectivity and auth. Returns the server's friendly name. */
    suspend fun testConnection(): String

    /** Loads every playable item across all libraries. */
    suspend fun loadLibrary(onProgress: (LoadProgress) -> Unit = {}): List<MediaItem>

    /** How to play [item], joining [offsetSeconds] in. Direct play when the device can, else an HLS transcode. */
    fun streamPlan(item: MediaItem, offsetSeconds: Long = 0, forceTranscode: Boolean = false): StreamPlan

    /** Server-side poster URL for an item, if it has artwork. */
    fun thumbnailUrl(item: MediaItem, width: Int = 400): String?
}
