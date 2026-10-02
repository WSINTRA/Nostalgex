package app.nostalgex.presentation

import app.nostalgex.filter.ChannelLineup
import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.schedule.DayPacker
import app.nostalgex.schedule.InMemoryManifestStore
import app.nostalgex.schedule.ScheduleResolver
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class GuideModelTest {
    private val clock = Clock.fixed(Instant.parse("2026-06-15T10:20:30Z"), ZoneOffset.UTC)
    private val pool = (1..6).map { MediaItem("m$it", "Movie $it", 90 + it * 5, MediaType.MOVIE) }
    private val resolver = ScheduleResolver(DayPacker(), InMemoryManifestStore(), clock, ZoneOffset.UTC)
    private val guide = GuideModel(resolver, clock, ZoneOffset.UTC)
    private fun lineup(n: Int, p: List<MediaItem> = pool) = ChannelLineup(Channel(n, n, "CH$n", "#000"), p)

    @Test fun `one row per channel in lineup order with now and next`() {
        val rows = guide.rows(listOf(lineup(2), lineup(1)))
        assertEquals(listOf(2, 1), rows.map { it.channel.number })
        val r = rows.first()
        assertNotNull(r.nowTitle); assertNotNull(r.nextTitle)
        assertTrue(r.nowTitle != r.nextTitle)
    }

    @Test fun `time labels are 12-hour in the injected zone and next starts when now ends`() {
        val r = guide.rows(listOf(lineup(1))).single()
        assertTrue(Regex("""\d{1,2}:\d{2} [AP]M""").matches(r.nowStartLabel), r.nowStartLabel)
        assertTrue(Regex("""\d{1,2}:\d{2} [AP]M""").matches(r.nextStartLabel!!), r.nextStartLabel)
        assertEquals(r.nowEndEpochSec, resolver.nowPlaying(lineup(1).channel, pool)!!.upNext!!.startEpochSec)
    }

    @Test fun `progress is between zero and one`() {
        val r = guide.rows(listOf(lineup(1))).single()
        assertTrue(r.progress in 0f..1f)
    }

    @Test fun `channels with nothing scheduled are omitted`() {
        assertEquals(listOf(1), guide.rows(listOf(lineup(1), lineup(2, emptyList()))).map { it.channel.number })
    }

    @Test fun `initial selection is the channel being watched, else the first`() {
        val rows = guide.rows(listOf(lineup(1), lineup(2), lineup(3)))
        assertEquals(1, GuideModel.indexOfChannel(rows, 2))
        assertEquals(0, GuideModel.indexOfChannel(rows, 99))
        assertEquals(0, GuideModel.indexOfChannel(emptyList(), 1))
    }
}
