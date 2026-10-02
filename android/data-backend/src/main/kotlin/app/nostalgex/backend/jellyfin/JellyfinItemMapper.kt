package app.nostalgex.backend.jellyfin

import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.time.Instant

/** Pure mapping from Jellyfin items to [MediaItem] (tvOS: parseMovieItem / fetchEpisodes). */
class JellyfinItemMapper {

    fun movie(dto: JellyfinItemDto, musicSection: Boolean): MediaItem? {
        val minutes = minutes(dto.RunTimeTicks)
        if (minutes <= 0) return null
        val genres = dto.Genres.orEmpty().toMutableList()
        if (musicSection && genres.none { it.contains("music", ignoreCase = true) }) genres += "Music Video"
        // A short item tagged Music inside a normal library also counts (musicals and concert films are far longer).
        val musicVideo = musicSection || (minutes <= SHORT_MUSIC_VIDEO_MAX && genres.any { it.contains("music", ignoreCase = true) })
        return base(dto, minutes).copy(
            title = dto.Name.orEmpty(),
            summary = dto.Overview.orEmpty(),
            year = dto.ProductionYear,
            premiereDate = dateOnly(dto.PremiereDate),
            contentRating = dto.OfficialRating,
            genres = genres,
            studios = dto.Studios.orEmpty().mapNotNull { it.Name }.take(1),
            communityRating = dto.CommunityRating ?: 0.0,
            type = MediaType.MOVIE,
            librarySource = if (musicVideo) LibrarySource.MUSIC_VIDEO else LibrarySource.MOVIE,
        )
    }

    /** Episodes carry the *show's* title, genres, rating and studio so channel rules key off the series. */
    fun episode(ep: JellyfinItemDto, show: JellyfinItemDto): MediaItem? {
        val minutes = minutes(ep.RunTimeTicks)
        if (minutes <= 0) return null
        val s = ep.ParentIndexNumber?.let { "S%02d".format(it) }.orEmpty()
        val e = ep.IndexNumber?.let { "E%02d".format(it) }.orEmpty()
        return base(ep, minutes).copy(
            title = show.Name ?: ep.SeriesName.orEmpty(),
            episodeTitle = ep.Name,
            seTag = (s + e).ifEmpty { null },
            summary = ep.Overview ?: show.Overview.orEmpty(),
            year = show.ProductionYear,
            premiereDate = dateOnly(ep.PremiereDate ?: show.PremiereDate),
            contentRating = show.OfficialRating ?: ep.OfficialRating,
            genres = show.Genres.orEmpty(),
            studios = show.Studios.orEmpty().mapNotNull { it.Name }.take(1),
            communityRating = show.CommunityRating ?: 0.0,
            type = MediaType.EPISODE,
            librarySource = LibrarySource.TV,
            thumbTag = ep.ImageTags?.get("Primary") ?: show.ImageTags?.get("Primary"),
        )
    }

    private fun base(dto: JellyfinItemDto, minutes: Int): MediaItem {
        val source = bestSource(dto.MediaSources)
        return MediaItem(
            id = dto.Id, title = "", durationMinutes = minutes, type = MediaType.MOVIE,
            viewCount = if (dto.UserData?.Played == true) 1 else 0,
            addedAtEpochSec = epochSeconds(dto.DateCreated),
            container = source?.Container,
            videoCodec = source?.video?.Codec,
            audioCodec = source?.audio?.Codec,
            videoProfile = source?.video?.Profile,
            videoBitDepth = source?.video?.BitDepth,
            videoWidth = source?.video?.Width,
            videoHeight = source?.video?.Height,
            bitrateKbps = source?.Bitrate?.div(1000),
            mediaSourceId = source?.Id ?: dto.Id,
            thumbTag = dto.ImageTags?.get("Primary"),
        )
    }

    /** Highest bitrate wins, ties on height; first source when none report a bitrate. */
    internal fun bestSource(sources: List<JellyfinItemDto.MediaSource>?): JellyfinItemDto.MediaSource? {
        if (sources.isNullOrEmpty()) return null
        if (sources.none { it.Bitrate != null }) return sources.first()
        return sources.maxWith(compareBy({ it.Bitrate ?: Int.MIN_VALUE }, { it.video?.Height ?: 0 }))
    }

    /** Jellyfin runtimes are 100 ns ticks; 600,000,000 ticks is one minute. */
    private fun minutes(ticks: Long?): Int = ((ticks ?: 0L) / TICKS_PER_MINUTE).toInt()

    private fun dateOnly(iso: String?): String? = iso?.takeIf { it.length >= 10 }?.substring(0, 10)

    private fun epochSeconds(iso: String?): Long =
        try { iso?.let { Instant.parse(it).epochSecond } ?: 0L } catch (e: Exception) { 0L }

    private companion object {
        const val TICKS_PER_MINUTE = 600_000_000L
        const val SHORT_MUSIC_VIDEO_MAX = 10
    }
}
