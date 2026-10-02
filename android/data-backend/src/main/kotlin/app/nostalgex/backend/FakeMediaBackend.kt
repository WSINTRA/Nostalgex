package app.nostalgex.backend

import app.nostalgex.model.MediaItem

/** In-memory backend for tests of anything that depends on [MediaBackend]. */
class FakeMediaBackend(
    private val items: List<MediaItem> = emptyList(),
    private val serverName: String = "Fake Server",
    private val failure: Throwable? = null,
    override val serverId: String = "fake",
) : MediaBackend {
    override val authHeaders: Map<String, String> = mapOf("X-Fake" to "1")

    override suspend fun testConnection(): String = failure?.let { throw it } ?: serverName

    override suspend fun loadLibrary(onProgress: (LoadProgress) -> Unit): List<MediaItem> {
        failure?.let { throw it }
        onProgress(LoadProgress(1, 1, "Fake", items.size))
        return items
    }

    override fun thumbnailUrl(item: MediaItem, width: Int): String? = "http://fake/${item.id}/$width"
}
