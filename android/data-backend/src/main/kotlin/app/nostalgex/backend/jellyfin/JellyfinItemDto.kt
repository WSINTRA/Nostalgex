package app.nostalgex.backend.jellyfin

import kotlinx.serialization.Serializable

/** Wire format of a Jellyfin BaseItem. Field names match the server's JSON. */
@Serializable
data class JellyfinItemDto(
    val Id: String,
    val Name: String? = null,
    val SeriesName: String? = null,
    val Overview: String? = null,
    val ProductionYear: Int? = null,
    val PremiereDate: String? = null,
    val DateCreated: String? = null,
    val OfficialRating: String? = null,
    val CommunityRating: Double? = null,
    val RunTimeTicks: Long? = null,
    val Genres: List<String>? = null,
    val CollectionType: String? = null,
    val ParentIndexNumber: Int? = null,
    val IndexNumber: Int? = null,
    val Studios: List<Studio>? = null,
    val MediaSources: List<MediaSource>? = null,
    val ImageTags: Map<String, String>? = null,
    val UserData: UserData? = null,
) {
    @Serializable data class Studio(val Name: String? = null)
    @Serializable data class UserData(val Played: Boolean? = null)

    @Serializable
    data class MediaSource(
        val Id: String? = null,
        val Container: String? = null,
        val Bitrate: Int? = null,
        val MediaStreams: List<MediaStream>? = null,
    ) {
        val video get() = MediaStreams?.firstOrNull { it.Type == "Video" }
        val audio get() = MediaStreams?.firstOrNull { it.Type == "Audio" }
    }

    @Serializable
    data class MediaStream(
        val Type: String? = null,
        val Codec: String? = null,
        val Profile: String? = null,
        val Width: Int? = null,
        val Height: Int? = null,
        val BitDepth: Int? = null,
    )
}

@Serializable
internal data class ItemsResponseDto(val Items: List<JellyfinItemDto>? = null, val TotalRecordCount: Int? = null)
