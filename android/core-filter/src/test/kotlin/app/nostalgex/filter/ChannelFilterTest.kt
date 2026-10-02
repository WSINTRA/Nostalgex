package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.GenreRules
import app.nostalgex.model.IntRange2
import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChannelFilterTest {
    private val filter = ChannelFilter()

    private fun ch(rules: ChannelRules = ChannelRules(), category: String? = null) =
        Channel(id = 1, number = 1, name = "T", colorHex = "#000", category = category, rules = rules)

    private fun movie(
        title: String = "Heat", genres: List<String> = listOf("Action"), year: Int? = 1995,
        rating: String? = "R", minutes: Int = 120, studio: String? = null,
        source: LibrarySource? = null, type: MediaType = MediaType.MOVIE, premiere: String? = null,
    ) = MediaItem(
        id = title, title = title, durationMinutes = minutes, type = type, year = year,
        contentRating = rating, genres = genres, studios = listOfNotNull(studio),
        librarySource = source, premiereDate = premiere,
    )

    private fun passes(item: MediaItem, channel: Channel) = filter.passes(item, channel)

    // --- no rules ---
    @Test fun `channel with no rules accepts ordinary items`() = assertTrue(passes(movie(), ch()))

    // --- type ---
    @Test fun `type rule restricts movie vs episode`() {
        val c = ch(ChannelRules(type = MediaType.MOVIE))
        assertTrue(passes(movie(), c))
        assertFalse(passes(movie(type = MediaType.EPISODE), c))
    }

    // --- source ---
    @Test fun `music videos are excluded unless channel opts in`() {
        val mv = movie(source = LibrarySource.MUSIC_VIDEO)
        assertFalse(passes(mv, ch()))
        assertTrue(passes(mv, ch(ChannelRules(source = LibrarySource.MUSIC_VIDEO))))
    }

    @Test fun `source rule requires matching library, null source counts as movie`() {
        val c = ch(ChannelRules(source = LibrarySource.TV))
        assertFalse(passes(movie(source = null), c))
        assertTrue(passes(movie(source = LibrarySource.TV, type = MediaType.EPISODE), c))
        assertTrue(passes(movie(source = null), ch(ChannelRules(source = LibrarySource.MOVIE))))
    }

    // --- genre include / exclude / requireAll ---
    @Test fun `genre include matches by case-insensitive substring`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("comedy"))))
        assertTrue(passes(movie(genres = listOf("Romantic Comedy")), c))
        assertFalse(passes(movie(genres = listOf("Drama")), c))
    }

    @Test fun `genre exclude blocks`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Comedy"), exclude = listOf("Family"))))
        assertFalse(passes(movie(genres = listOf("Comedy", "Family")), c))
        assertTrue(passes(movie(genres = listOf("Comedy")), c))
    }

    @Test fun `genre requireAll needs every genre`() {
        val c = ch(ChannelRules(genres = GenreRules(requireAll = listOf("Comedy", "Crime"))))
        assertTrue(passes(movie(genres = listOf("Comedy", "Crime")), c))
        assertFalse(passes(movie(genres = listOf("Comedy")), c))
    }

    // --- genre locks ---
    @Test fun `horror is locked out of channels that do not include it`() {
        val horror = movie(genres = listOf("Horror", "Comedy"))
        val comedy = ch(ChannelRules(genres = GenreRules(include = listOf("Comedy"))))
        val horrorCh = ch(ChannelRules(genres = GenreRules(include = listOf("Horror"))))
        assertFalse(passes(horror, comedy))
        assertTrue(passes(horror, horrorCh))
    }

    @Test fun `animation is allowed on kids channels and animation channels only`() {
        val toon = movie(genres = listOf("Animation", "Comedy"), rating = "G")
        val comedy = ch(ChannelRules(genres = GenreRules(include = listOf("Comedy"))))
        val kids = ch(ChannelRules(genres = GenreRules(include = listOf("Comedy"))), category = "kids")
        assertFalse(passes(toon, comedy))
        assertTrue(passes(toon, kids))
        assertTrue(passes(toon, ch(ChannelRules(genres = GenreRules(include = listOf("Animation"))))))
    }

    @Test fun `studio only channels bypass genre locks`() {
        val toon = movie(genres = listOf("Animation"), studio = "Pixar Animation Studios", rating = "G")
        assertTrue(passes(toon, ch(ChannelRules(studios = listOf("Pixar")))))
    }

    @Test fun `documentary war western and talk show are locked`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Drama"))))
        for (g in listOf("Documentary", "War", "Western", "Talk Show", "Reality")) {
            assertFalse(passes(movie(genres = listOf("Drama", g)), c), g)
        }
    }

    @Test fun `sport and music genres are not locked`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Drama"))))
        assertTrue(passes(movie(genres = listOf("Drama", "Sport")), c))
        assertTrue(passes(movie(genres = listOf("Drama", "Music")), c))
    }

    @Test fun `explicit reality channel requires a reality genre`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Reality"))))
        assertTrue(passes(movie(genres = listOf("Reality")), c))
        assertFalse(passes(movie(genres = listOf("Comedy")), c))
    }

    // --- family safety ---
    @Test fun `kids and family channels reject adult ratings`() {
        val kids = ch(category = "kids")
        assertFalse(passes(movie(rating = "R"), kids))
        assertFalse(passes(movie(rating = "TV-MA"), kids))
        assertTrue(passes(movie(rating = "PG"), kids))
        assertTrue(passes(movie(rating = null), kids))
        val family = ch(ChannelRules(genres = GenreRules(include = listOf("Family"))))
        assertFalse(passes(movie(genres = listOf("Family"), rating = "NC-17"), family))
    }

    // --- year ---
    @Test fun `year range is inclusive and unknown year passes`() {
        val c = ch(ChannelRules(yearRange = IntRange2(1980, 1989)))
        assertTrue(passes(movie(year = 1980), c))
        assertTrue(passes(movie(year = 1989), c))
        assertFalse(passes(movie(year = 1979), c))
        assertFalse(passes(movie(year = 1990), c))
        assertTrue(passes(movie(year = null), c))
    }

    @Test fun `year falls back to premiere date`() {
        val c = ch(ChannelRules(yearRange = IntRange2(1980, 1989)))
        assertTrue(passes(movie(year = null, premiere = "1985-06-01"), c))
        assertFalse(passes(movie(year = null, premiere = "1999-06-01"), c))
    }

    // --- content ratings ---
    @Test fun `content ratings is an allow list`() {
        val c = ch(ChannelRules(contentRatings = listOf("PG", "PG-13")))
        assertTrue(passes(movie(rating = "PG"), c))
        assertFalse(passes(movie(rating = "R"), c))
        assertFalse(passes(movie(rating = null), c))
    }

    @Test fun `unrated passes only when allowUnrated`() {
        val c = ch(ChannelRules(contentRatings = listOf("PG"), allowUnrated = true))
        assertTrue(passes(movie(rating = null), c))
        assertFalse(passes(movie(rating = "R"), c))
    }

    // --- duration ---
    @Test fun `duration range bounds in minutes`() {
        val c = ch(ChannelRules(durationRange = IntRange2(30, 100)))
        assertTrue(passes(movie(minutes = 30), c))
        assertTrue(passes(movie(minutes = 100), c))
        assertFalse(passes(movie(minutes = 29), c))
        assertFalse(passes(movie(minutes = 101), c))
    }

    // --- studio ---
    @Test fun `studio match is case-insensitive substring`() {
        val c = ch(ChannelRules(studios = listOf("disney")))
        assertTrue(passes(movie(studio = "Walt Disney Pictures", genres = listOf("Family"), rating = "G"), c))
        assertFalse(passes(movie(studio = "Paramount"), c))
        assertFalse(passes(movie(studio = null), c))
    }

    @Test fun `studio plus genre requires both`() {
        val c = ch(ChannelRules(studios = listOf("Disney"), genres = GenreRules(include = listOf("Comedy"))))
        assertTrue(passes(movie(studio = "Disney", genres = listOf("Comedy"), rating = "PG"), c))
        assertFalse(passes(movie(studio = "Disney", genres = listOf("Drama"), rating = "PG"), c))
        assertFalse(passes(movie(studio = "Fox", genres = listOf("Comedy"), rating = "PG"), c))
    }

    // --- pool ---
    @Test fun `pool filters a library`() {
        val c = ch(ChannelRules(type = MediaType.MOVIE, yearRange = IntRange2(1990, 1999)))
        val pool = filter.pool(listOf(movie("A", year = 1995), movie("B", year = 2005)), c)
        assertEquals(listOf("A"), pool.map { it.title })
    }
}
