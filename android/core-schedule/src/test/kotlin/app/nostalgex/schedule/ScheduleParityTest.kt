package app.nostalgex.schedule

import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Reads the golden vectors directly from scripts/nostalgex-schedule-order-smoke.mjs (copied in by
 * Gradle). Those strings were produced from the real Swift code, so if they change and this
 * implementation does not, this test fails.
 */
class ScheduleParityTest {
    private val source = checkNotNull(javaClass.classLoader.getResource("nostalgex-schedule-order-smoke.mjs")) {
        "smoke file not copied"
    }.readText()

    private val dayStart = 1_700_100_000L
    private val pool: List<MediaItem> = buildList {
        listOf("Seinfeld", "Friends", "The Office").forEachIndexed { si, show ->
            for (e in 1..5) add(MediaItem("e$si$e", show, 22, MediaType.EPISODE))
        }
        listOf(
            "Alien", "Mockingjay Part 2", "Heat", "Mockingjay Part 1", "Deathly Hallows: Part 2",
            "Jaws", "Deathly Hallows: Part 1", "Rocky", "Kill Bill Vol 1", "Dune",
        ).forEachIndexed { mi, title ->
            add(MediaItem("m$mi", title, 95 + mi * 3, MediaType.MOVIE, addedAtEpochSec = if (mi % 4 == 0) 1_700_000_000L else 0L))
        }
    }

    private val goldens = Regex(""""(INTER|PROMO|SEQ):(\d+):(\d+)":\s*"([^"]+)"""").findAll(source)
        .associate { Triple(it.groupValues[1], it.groupValues[2].toInt(), it.groupValues[3].toInt()) to it.groupValues[4] }

    private val offsets = Regex(""""(\d+):(\w+)":\s*(\d+)""").findAll(source.substringAfter("const OFFSETS"))
        .map { Triple(it.groupValues[1].toInt(), it.groupValues[2], it.groupValues[3].toInt()) }.toList()

    private fun List<MediaItem>.ids() = joinToString(",") { it.id }

    @Test fun `the vectors were actually found in the JS file`() {
        assertEquals(9, goldens.size, "expected 3 seeds x INTER/PROMO/SEQ")
        assertEquals(12, offsets.size, "expected 12 premiereOffset vectors")
    }

    @Test fun `ordering matches every golden vector in the JS smoke test`() {
        for ((seed, day) in goldens.keys.map { it.second to it.third }.distinct()) {
            val a = SchedulePoolOrdering.interleaveByShow(pool, seed, day)
            assertEquals(goldens.getValue(Triple("INTER", seed, day)), a.ids(), "INTER $seed:$day")
            val b = SchedulePoolOrdering.promoteRecentlyAdded(a, dayStart, seed)
            assertEquals(goldens.getValue(Triple("PROMO", seed, day)), b.ids(), "PROMO $seed:$day")
            assertEquals(goldens.getValue(Triple("SEQ", seed, day)), SchedulePoolOrdering.groupSequelParts(b).ids(), "SEQ $seed:$day")
        }
    }

    @Test fun `premiere offsets match every Swift vector in the JS smoke test`() {
        for ((channel, key, want) in offsets) {
            assertEquals(want, SchedulePoolOrdering.premiereOffset(channel, key), "premiereOffset($channel, $key)")
        }
    }

    @Test fun `no two premiere offsets fall outside the prime-time window`() {
        assertTrue(offsets.all { it.third in 19 * 3600..24 * 3600 })
    }
}
