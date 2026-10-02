package app.nostalgex.schedule

import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScheduleResolverTest {
    private val channel = Channel(id = 7, number = 7, name = "T", colorHex = "#000")
    private val pool = (1..6).map { MediaItem("m$it", "Movie $it", 90 + it * 5, MediaType.MOVIE) }

    private fun resolver(at: String, store: ManifestStore = InMemoryManifestStore()) =
        ScheduleResolver(DayPacker(), store, Clock.fixed(Instant.parse(at), ZoneOffset.UTC), ZoneOffset.UTC)

    @Test fun `now playing block contains now and offset is seconds into it`() {
        val r = resolver("2026-06-15T10:20:30Z")
        val np = assertNotNull(r.nowPlaying(channel, pool))
        val now = Instant.parse("2026-06-15T10:20:30Z").epochSecond
        assertTrue(np.block.contains(now))
        assertEquals(now - np.block.startEpochSec, np.offsetSeconds)
    }

    @Test fun `up next starts when now playing ends`() {
        val np = assertNotNull(resolver("2026-06-15T10:20:30Z").nowPlaying(channel, pool))
        assertEquals(np.block.endEpochSec, np.upNext?.startEpochSec)
    }

    @Test fun `up next crosses midnight`() {
        val np = assertNotNull(resolver("2026-06-15T23:59:59Z").nowPlaying(channel, pool))
        val midnight = Instant.parse("2026-06-16T00:00:00Z").epochSecond
        assertEquals(midnight, np.upNext?.startEpochSec)
    }

    @Test fun `same time gives same schedule across resolvers`() {
        val a = resolver("2026-06-15T10:20:30Z").nowPlaying(channel, pool)
        val b = resolver("2026-06-15T10:20:30Z").nowPlaying(channel, pool)
        assertEquals(a, b)
    }

    @Test fun `day is persisted and reused`() {
        val store = InMemoryManifestStore()
        resolver("2026-06-15T10:00:00Z", store).nowPlaying(channel, pool)
        assertNotNull(store.load(7, "2026-06-15"))
    }

    @Test fun `cached day is reused if pool unchanged, rebuilt if changed`() {
        val store = InMemoryManifestStore()
        val first = resolver("2026-06-15T10:00:00Z", store).blocksForDay(channel, pool, java.time.LocalDate.parse("2026-06-15"))
        val again = resolver("2026-06-15T10:00:00Z", store).blocksForDay(channel, pool, java.time.LocalDate.parse("2026-06-15"))
        assertEquals(first, again)
        val smaller = pool.drop(2)
        val rebuilt = resolver("2026-06-15T10:00:00Z", store).blocksForDay(channel, smaller, java.time.LocalDate.parse("2026-06-15"))
        assertTrue(rebuilt.all { b -> smaller.any { it.id == b.item.id } })
    }

    @Test fun `yesterday's stored titles feed into today`() {
        val store = InMemoryManifestStore()
        val r = resolver("2026-06-15T10:00:00Z", store)
        val y = r.blocksForDay(channel, pool, java.time.LocalDate.parse("2026-06-14"))
        val today = r.blocksForDay(channel, pool, java.time.LocalDate.parse("2026-06-15"))
        assertTrue(today.first().item.id != y.last().item.id)
    }

    @Test fun `range returns blocks intersecting the window`() {
        val r = resolver("2026-06-15T10:00:00Z")
        val from = Instant.parse("2026-06-15T10:00:00Z").epochSecond
        val blocks = r.blocksInRange(channel, pool, from, from + 7200)
        assertTrue(blocks.isNotEmpty())
        assertTrue(blocks.all { it.endEpochSec > from && it.startEpochSec < from + 7200 })
    }

    @Test fun `empty pool gives null`() = assertNull(resolver("2026-06-15T10:00:00Z").nowPlaying(channel, emptyList()))
}
