package app.nostalgex.presentation

/** One horizontal piece of a guide row: empty space or a program, as a fraction of the row width. */
sealed interface RowSegment {
    val fraction: Float
    data class Gap(override val fraction: Float) : RowSegment
    /** [index] points back into the intervals passed to [ProgramRowLayout.segments]. */
    data class Block(val index: Int, override val fraction: Float) : RowSegment
}

/**
 * Turns program intervals into row segments for a time window (port of tvOS `ProgramRowLayout`).
 * A cursor walks left to right, so gaps keep their true position, overlaps cannot widen the row,
 * and the fractions never sum past 1.
 */
object ProgramRowLayout {
    fun segments(intervals: List<Pair<Long, Long>>, windowStartSec: Long, windowDurationSec: Long): List<RowSegment> {
        if (windowDurationSec <= 0) return emptyList()
        val windowEnd = windowStartSec + windowDurationSec
        val out = ArrayList<RowSegment>()
        var cursor = windowStartSec
        intervals.withIndex().sortedBy { it.value.first }.forEach { (i, iv) ->
            val start = maxOf(iv.first, cursor)
            val end = minOf(iv.second, windowEnd)
            if (end <= start) return@forEach
            if (start > cursor) out += RowSegment.Gap((start - cursor).toFloat() / windowDurationSec)
            out += RowSegment.Block(i, (end - start).toFloat() / windowDurationSec)
            cursor = end
        }
        return out
    }
}
