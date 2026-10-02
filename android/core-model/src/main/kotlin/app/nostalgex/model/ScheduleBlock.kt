package app.nostalgex.model

/** One program slot on a channel, in absolute unix seconds. */
data class ScheduleBlock(
    val item: MediaItem,
    val startEpochSec: Long,
    val endEpochSec: Long,
) {
    val durationSeconds: Long get() = endEpochSec - startEpochSec

    fun contains(epochSec: Long): Boolean = epochSec >= startEpochSec && epochSec < endEpochSec

    /** Seconds into the program at [epochSec], clamped to be non-negative. */
    fun offsetAt(epochSec: Long): Long = maxOf(0L, epochSec - startEpochSec)
}
