package app.nostalgex.backend.jellyfin

import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class JellyfinItemMapperTest {
    private val mapper = JellyfinItemMapper()
    private val min = 600_000_000L

    private fun src(id: String, bitrate: Int?, height: Int = 1080, codec: String = "h264") = JellyfinItemDto.MediaSource(
        Id = id, Container = "mkv", Bitrate = bitrate,
        MediaStreams = listOf(
            JellyfinItemDto.MediaStream(Type = "Video", Codec = codec, Profile = "High", Height = height, Width = 1920, BitDepth = 8),
            JellyfinItemDto.MediaStream(Type = "Audio", Codec = "aac"),
        ),
    )

    private val movie = JellyfinItemDto(
        Id = "m1", Name = "Heat", Overview = "Cops", ProductionYear = 1995, PremiereDate = "1995-12-15T00:00:00.0000000Z",
        DateCreated = "2024-01-01T00:00:00.0000000Z", OfficialRating = "R", CommunityRating = 8.2, RunTimeTicks = 170 * min,
        Genres = listOf("Action"), Studios = listOf(JellyfinItemDto.StudioDto("Warner")),
        MediaSources = listOf(src("s1", 4_000_000)), UserData = JellyfinItemDto.UserDataDto(Played = true),
    )

    @Test fun `movie maps core fields`() {
        val m = mapper.movie(movie, musicSection = false)!!
        assertEquals("m1", m.id); assertEquals("Heat", m.title); assertEquals(170, m.durationMinutes)
        assertEquals(MediaType.MOVIE, m.type); assertEquals(1995, m.year); assertEquals("R", m.contentRating)
        assertEquals(listOf("Action"), m.genres); assertEquals(listOf("Warner"), m.studios)
        assertEquals(8.2, m.communityRating); assertEquals(1, m.viewCount)
        assertEquals("1995-12-15", m.premiereDate); assertEquals(1704067200L, m.addedAtEpochSec)
        assertEquals(LibrarySource.MOVIE, m.librarySource)
    }

    @Test fun `movie maps stream facts from the best source`() {
        val dto = movie.copy(MediaSources = listOf(src("lo", 1_000_000, 720), src("hi", 8_000_000, 2160, "hevc")))
        val m = mapper.movie(dto, false)!!
        assertEquals("hi", m.mediaSourceId); assertEquals("hevc", m.videoCodec); assertEquals("aac", m.audioCodec)
        assertEquals("mkv", m.container); assertEquals(8000, m.bitrateKbps); assertEquals(2160, m.videoHeight)
        assertEquals(8, m.videoBitDepth); assertEquals("High", m.videoProfile)
    }

    @Test fun `no bitrates falls back to first source`() {
        val dto = movie.copy(MediaSources = listOf(src("a", null), src("b", null)))
        assertEquals("a", mapper.movie(dto, false)!!.mediaSourceId)
    }

    @Test fun `zero runtime is dropped`() = assertNull(mapper.movie(movie.copy(RunTimeTicks = 0), false))
    @Test fun `missing runtime is dropped`() = assertNull(mapper.movie(movie.copy(RunTimeTicks = null), false))

    @Test fun `music section items become music videos`() {
        val m = mapper.movie(movie.copy(Genres = listOf("Pop")), musicSection = true)!!
        assertEquals(LibrarySource.MUSIC_VIDEO, m.librarySource)
        assertEquals(listOf("Pop", "Music Video"), m.genres)
    }

    @Test fun `short music-tagged movie is a music video, long one is not`() {
        val short = mapper.movie(movie.copy(RunTimeTicks = 4 * min, Genres = listOf("Music")), false)!!
        assertEquals(LibrarySource.MUSIC_VIDEO, short.librarySource)
        val long = mapper.movie(movie.copy(RunTimeTicks = 120 * min, Genres = listOf("Music")), false)!!
        assertEquals(LibrarySource.MOVIE, long.librarySource)
    }

    @Test fun `episode inherits show metadata and builds SxxExx tag`() {
        val show = JellyfinItemDto(Id = "sh", Name = "Seinfeld", Overview = "Nothing", ProductionYear = 1989, OfficialRating = "TV-PG",
            CommunityRating = 8.9, Genres = listOf("Comedy"), Studios = listOf(JellyfinItemDto.StudioDto("NBC")))
        val ep = JellyfinItemDto(Id = "e1", Name = "The Pilot", RunTimeTicks = 22 * min, ParentIndexNumber = 1, IndexNumber = 4,
            MediaSources = listOf(src("es", 1000)), DateCreated = "2024-01-01T00:00:00Z")
        val m = mapper.episode(ep, show)!!
        assertEquals("Seinfeld", m.title); assertEquals("The Pilot", m.episodeTitle); assertEquals("S01E04", m.seTag)
        assertEquals(MediaType.EPISODE, m.type); assertEquals(LibrarySource.TV, m.librarySource)
        assertEquals(listOf("Comedy"), m.genres); assertEquals("TV-PG", m.contentRating); assertEquals(1989, m.year)
        assertEquals(listOf("NBC"), m.studios); assertEquals("es", m.mediaSourceId)
    }

    @Test fun `episode without runtime is dropped and missing numbers give no tag`() {
        val show = JellyfinItemDto(Id = "sh", Name = "S")
        assertNull(mapper.episode(JellyfinItemDto(Id = "e", RunTimeTicks = 0), show))
        assertNull(mapper.episode(JellyfinItemDto(Id = "e", RunTimeTicks = 5 * min), show)!!.seTag)
    }

    @Test fun `bad date strings do not crash`() {
        assertEquals(0L, mapper.movie(movie.copy(DateCreated = "garbage"), false)!!.addedAtEpochSec)
        assertNull(mapper.movie(movie.copy(PremiereDate = null), false)!!.premiereDate)
    }
}
