package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.ExclusiveRule
import app.nostalgex.model.GenreRules
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChannelFilterRulesTest {
    // 2026-06-15 12:00 UTC
    private val now = Instant.parse("2026-06-15T12:00:00Z")
    private val clock = Clock.fixed(now, ZoneOffset.UTC)

    private fun filter(vararg ex: ExclusiveRule) = ChannelFilter(ex.toList(), clock)
    private fun ch(rules: ChannelRules, id: Int = 1) = Channel(id = id, number = id, name = "T", colorHex = "#000", rules = rules)

    private fun item(
        title: String = "Heat", genres: List<String> = listOf("Drama"), year: Int? = 1995, views: Int = 0,
        added: Long = 0, premiere: String? = null, rating: Double = 0.0,
    ) = MediaItem(
        id = title, title = title, durationMinutes = 100, type = MediaType.MOVIE, year = year,
        genres = genres, viewCount = views, addedAtEpochSec = added, premiereDate = premiere, communityRating = rating,
    )

    // --- title rules ---
    @Test fun `titleContains matches whole words only, case-insensitive`() {
        val c = ch(ChannelRules(titleContains = listOf("santa")))
        assertTrue(filter().passes(item("The Santa Clause"), c))
        assertFalse(filter().passes(item("Santana Live"), c))
    }

    @Test fun `title-curated channel ignores genre lists`() {
        val c = ch(ChannelRules(titleContains = listOf("Simpsons")))
        assertTrue(filter().passes(item("The Simpsons", genres = listOf("Comedy")), c))
        assertFalse(filter().passes(item("Heat"), c))
    }

    @Test fun `titleContains with genre include passes on either`() {
        val c = ch(ChannelRules(titleContains = listOf("Alien"), genres = GenreRules(include = listOf("Sci-Fi"))))
        assertTrue(filter().passes(item("Alien", genres = listOf("Horror", "Sci-Fi")), c.copy(rules = c.rules.copy(genres = GenreRules(include = listOf("Sci-Fi", "Horror"))))))
        assertTrue(filter().passes(item("Dune", genres = listOf("Sci-Fi")), c))
        assertFalse(filter().passes(item("Heat", genres = listOf("Drama")), c))
    }

    @Test fun `year suffix is ignored when matching titles`() {
        val c = ch(ChannelRules(titleContains = listOf("Elf")))
        assertTrue(filter().passes(item("Elf (2003)"), c))
    }

    @Test fun `titleExcludes rejects`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Drama")), titleExcludes = listOf("Heat")))
        assertFalse(filter().passes(item("Heat"), c))
        assertTrue(filter().passes(item("Casino"), c))
    }

    // --- editorial overrides ---
    @Test fun `editorial override passes regardless of other rules`() {
        val c = ch(ChannelRules(genres = GenreRules(include = listOf("Comedy")), editorialOverrides = listOf("Gremlins")))
        assertTrue(filter().passes(item("Gremlins", genres = listOf("Drama"), year = 1984), c))
    }

    @Test fun `editorial override still respects genre locks`() {
        val c = ch(ChannelRules(editorialOverrides = listOf("Gremlins")))
        assertFalse(filter().passes(item("Gremlins", genres = listOf("Horror")), c))
    }

    // --- exclusive rules ---
    @Test fun `exclusive rule blocks content from other channels but not owners`() {
        val rule = ExclusiveRule(channelIds = listOf(32), genres = listOf("Anime"))
        val anime = item("Akira", genres = listOf("Anime"))
        val f = filter(rule)
        assertFalse(f.passes(anime, ch(ChannelRules(), id = 5)))
        assertTrue(f.passes(anime, ch(ChannelRules(), id = 32)))
    }

    @Test fun `exclusive editorial titles ignore year suffix`() {
        val f = filter(ExclusiveRule(channelIds = listOf(130), editorialTitles = listOf("Elf")))
        assertFalse(f.passes(item("Elf (2003)"), ch(ChannelRules(), id = 9)))
    }

    // --- watch history ---
    @Test fun `watchedOnly needs a view unless it is a new release`() {
        val c = ch(ChannelRules(watchedOnly = true))
        assertFalse(filter().passes(item(views = 0, year = 1995), c))
        assertTrue(filter().passes(item(views = 1, year = 1995), c))
        assertTrue(filter().passes(item(views = 0, year = 2025), c)) // new release (>= year-1)
    }

    @Test fun `unwatchedOnly rejects viewed and new releases`() {
        val c = ch(ChannelRules(unwatchedOnly = true))
        assertTrue(filter().passes(item(views = 0, year = 1995), c))
        assertFalse(filter().passes(item(views = 1, year = 1995), c))
        assertFalse(filter().passes(item(views = 0, year = 2026), c))
    }

    @Test fun `rewatched needs three views`() {
        val c = ch(ChannelRules(rewatched = true))
        assertFalse(filter().passes(item(views = 2), c))
        assertTrue(filter().passes(item(views = 3), c))
    }

    // --- recency ---
    @Test fun `addedWithinDays uses the injected clock`() {
        val c = ch(ChannelRules(addedWithinDays = 30))
        val day = 86_400L
        assertTrue(filter().passes(item(added = now.epochSecond - 10 * day), c))
        assertFalse(filter().passes(item(added = now.epochSecond - 40 * day), c))
        assertFalse(filter().passes(item(added = 0), c))
    }

    @Test fun `releasedWithinMonths uses premiere date when present`() {
        val c = ch(ChannelRules(releasedWithinMonths = 6))
        assertTrue(filter().passes(item(premiere = "2026-03-01"), c))
        assertFalse(filter().passes(item(premiere = "2025-11-01"), c))
    }

    @Test fun `releasedWithinMonths falls back to year approximation`() {
        val c = ch(ChannelRules(releasedWithinMonths = 6)) // yearsBack = 0 -> year must be 2026
        assertTrue(filter().passes(item(year = 2026), c))
        assertFalse(filter().passes(item(year = 2025), c))
    }

    // --- rating ---
    @Test fun `ratingMin compares community rating`() {
        val c = ch(ChannelRules(ratingMin = 7.0))
        assertTrue(filter().passes(item(rating = 7.0), c))
        assertFalse(filter().passes(item(rating = 6.9), c))
    }

    // --- unsupported (enrichment) rules mirror tvOS with no enrichment record ---
    @Test fun `manifestOnly channels admit nothing without a manifest`() {
        assertFalse(filter().passes(item(), ch(ChannelRules(manifestOnly = true))))
    }

    @Test fun `keyword-only channels admit nothing without enrichment`() {
        assertFalse(filter().passes(item(), ch(ChannelRules(keywords = listOf("slasher")))))
    }
}
