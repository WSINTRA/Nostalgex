package app.nostalgex.model

import kotlinx.serialization.Serializable

enum class MediaType { MOVIE, EPISODE }

/** Which kind of library an item came from. Mirrors tvOS `LibrarySource`. */
enum class LibrarySource { MOVIE, TV, MUSIC_VIDEO }

/**
 * Backend-neutral playable item (tvOS: `PlexMediaItem`).
 *
 * For episodes, [title] is the *show* title (schedule interleaving groups on it) and
 * [episodeTitle] the episode name. [id] is the server's item id.
 */
@Serializable
data class MediaItem(
    val id: String,
    val title: String,
    val durationMinutes: Int,
    val type: MediaType,
    val episodeTitle: String? = null,
    val seTag: String? = null,
    val summary: String = "",
    val year: Int? = null,
    val contentRating: String? = null,
    val genres: List<String> = emptyList(),
    val studios: List<String> = emptyList(),
    val communityRating: Double = 0.0,
    val viewCount: Int = 0,
    val addedAtEpochSec: Long = 0,
    val premiereDate: String? = null,
    val librarySource: LibrarySource? = null,
    val container: String? = null,
    val videoCodec: String? = null,
    val audioCodec: String? = null,
    val videoBitDepth: Int? = null,
    val videoWidth: Int? = null,
    val videoHeight: Int? = null,
    val videoProfile: String? = null,
    val bitrateKbps: Int? = null,
    /** Backend-specific id of the file to play (Jellyfin MediaSourceId). */
    val mediaSourceId: String? = null,
    /** Image tag for the poster, used to cache-bust artwork URLs. */
    val thumbTag: String? = null,
) {
    /** Title without a trailing " (2003)" suffix that metadata agents add. */
    val titleWithoutYear: String get() = title.replace(YEAR_SUFFIX, "")

    private companion object {
        val YEAR_SUFFIX = Regex("""\s*\(\d{4}\)\s*$""")
    }
}
