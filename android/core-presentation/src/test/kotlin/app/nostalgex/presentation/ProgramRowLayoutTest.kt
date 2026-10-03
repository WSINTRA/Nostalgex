package app.nostalgex.presentation

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ProgramRowLayoutTest {
    private val w = 7200L

    @Test fun `back to back programs fill the window`() {
        val s = ProgramRowLayout.segments(listOf(0L to 3600L, 3600L to 7200L), 0, w)
        assertEquals(listOf(RowSegment.Block(0, 0.5f), RowSegment.Block(1, 0.5f)), s)
    }

    @Test fun `a program that started before the window is clipped to its visible part`() {
        val s = ProgramRowLayout.segments(listOf(-1800L to 1800L), 0, w)
        assertEquals(listOf(RowSegment.Block(0, 0.25f)), s)
    }

    @Test fun `a program running past the window is clipped`() {
        val s = ProgramRowLayout.segments(listOf(5400L to 20000L), 0, w)
        assertEquals(listOf(RowSegment.Gap(0.75f), RowSegment.Block(0, 0.25f)), s)
    }

    @Test fun `gaps keep their position`() {
        val s = ProgramRowLayout.segments(listOf(0L to 1800L, 3600L to 5400L), 0, w)
        assertEquals(listOf(RowSegment.Block(0, 0.25f), RowSegment.Gap(0.25f), RowSegment.Block(1, 0.25f)), s)
    }

    @Test fun `overlap cannot widen the row`() {
        val s = ProgramRowLayout.segments(listOf(0L to 5000L, 3000L to 9000L), 0, w)
        assertTrue(s.sumOf { it.fraction.toDouble() } <= 1.0 + 1e-6)
    }

    @Test fun `programs outside the window and a zero window give nothing`() {
        assertEquals(emptyList(), ProgramRowLayout.segments(listOf(9000L to 10000L), 0, w))
        assertEquals(emptyList(), ProgramRowLayout.segments(listOf(0L to 10L), 0, 0))
    }
}
