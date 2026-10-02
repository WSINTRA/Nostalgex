package app.nostalgex.schedule

import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/** Golden vectors copied from scripts/nostalgex-schedule-order-smoke.mjs (generated from real Swift). */
class PoolOrderingTest {
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

    private fun List<MediaItem>.ids() = joinToString(",") { it.id }

    private val golden = mapOf(
        Triple("INTER", 1, 20000) to "m8,m3,m5,m4,m7,m2,m6,m9,m0,e22,e25,e03,e01,m1,e15,e13,e23,e21,e04,e05,e14,e12,e24,e02,e11",
        Triple("PROMO", 1, 20000) to "m3,m5,m7,m2,m6,m9,e22,e25,e03,e01,m1,e15,e13,e23,e21,e04,e05,e14,e12,e24,e02,e11,m0,m4,m8",
        Triple("SEQ", 1, 20000) to "m3,m1,m5,m7,m2,m6,m4,m9,e22,e25,e03,e01,e15,e13,e23,e21,e04,e05,e14,e12,e24,e02,e11,m0,m8",
        Triple("INTER", 49, 20431) to "m1,e23,e24,m7,m3,m2,m9,m0,m5,m4,e03,e05,e14,e12,m8,m6,e22,e21,e02,e04,e11,e15,e25,e01,e13",
        Triple("PROMO", 49, 20431) to "m1,e23,e24,m7,m3,m2,m9,m5,e03,e05,e14,e12,m6,e22,e21,e02,e04,e11,e15,e25,e01,e13,m0,m8,m4",
        Triple("SEQ", 49, 20431) to "m3,m1,e23,e24,m7,m2,m9,m5,e03,e05,e14,e12,m6,m4,e22,e21,e02,e04,e11,e15,e25,e01,e13,m0,m8",
        Triple("INTER", 141, 20500) to "m8,m9,m6,m2,m4,m3,m1,e21,e22,m5,e04,e05,m7,e12,e11,m0,e25,e24,e02,e01,e15,e13,e23,e03,e14",
        Triple("PROMO", 141, 20500) to "m9,m6,m2,m3,m1,e21,e22,m5,e04,e05,m7,e12,e11,e25,e24,e02,e01,e15,e13,e23,e03,e14,m4,m8,m0",
        Triple("SEQ", 141, 20500) to "m9,m6,m4,m2,m3,m1,e21,e22,m5,e04,e05,m7,e12,e11,e25,e24,e02,e01,e15,e13,e23,e03,e14,m8,m0",
    )

    @Test fun `interleave, promote and sequel grouping match golden vectors`() {
        for ((seed, day) in listOf(1 to 20000, 49 to 20431, 141 to 20500)) {
            val a = SchedulePoolOrdering.interleaveByShow(pool, seed, day)
            assertEquals(golden.getValue(Triple("INTER", seed, day)), a.ids(), "INTER $seed:$day")
            val b = SchedulePoolOrdering.promoteRecentlyAdded(a, dayStart, seed)
            assertEquals(golden.getValue(Triple("PROMO", seed, day)), b.ids(), "PROMO $seed:$day")
            val c = SchedulePoolOrdering.groupSequelParts(b)
            assertEquals(golden.getValue(Triple("SEQ", seed, day)), c.ids(), "SEQ $seed:$day")
        }
    }

    @Test fun `premiereOffset matches Swift vectors`() {
        val want = mapOf(
            1 to "m0" to 72900, 1 to "m4" to 79200, 1 to "m8" to 81000, 1 to "e01" to 84600,
            49 to "m0" to 68400, 49 to "m4" to 85500, 49 to "m8" to 78300, 49 to "e01" to 76500,
            223 to "m0" to 83700, 223 to "m4" to 73800, 223 to "m8" to 69300, 223 to "e01" to 72000,
        )
        for ((k, v) in want) assertEquals(v, SchedulePoolOrdering.premiereOffset(k.first, k.second), "${k.first}:${k.second}")
    }

    @Test fun `never more than two consecutive episodes of one show`() {
        val out = SchedulePoolOrdering.interleaveByShow(pool, 7, 20000)
        var run = 1; var max = 1
        for (i in 1 until out.size) {
            run = if (out[i].type == MediaType.EPISODE && out[i].title == out[i - 1].title) run + 1 else 1
            max = maxOf(max, run)
        }
        assertTrue(max <= 2)
    }

    @Test fun `lone Part 2 does not move`() {
        val lone = listOf(MediaItem("a", "Alien", 100, MediaType.MOVIE), MediaItem("b", "Some Story Part 2", 100, MediaType.MOVIE))
        assertEquals("a,b", SchedulePoolOrdering.groupSequelParts(lone).ids())
    }

    @Test fun `premiere lands at prime time not position zero`() {
        val recent = pool.mapIndexed { n, i -> i.copy(addedAtEpochSec = if (n == 0) dayStart - 3600 else 0) }
        val out = SchedulePoolOrdering.promoteRecentlyAdded(recent, dayStart, 1)
        assertNotEquals("e01", out.first().id)
        assertTrue(out.any { it.id == "e01" })
    }
}
