package app.nostalgex.schedule

import app.nostalgex.model.MediaItem
import app.nostalgex.model.ScheduleBlock

/** Inputs for packing one channel-day. Everything is explicit so packing stays pure. */
data class DayPackRequest(
    val pool: List<MediaItem>,
    val dayStartEpochSec: Long,
    val dayNumber: Int,
    val channelId: Int,
    val isPremiereChannel: Boolean = false,
    /** Ids aired yesterday on this channel; they go to the back of the queue. */
    val yesterdayAired: Set<String> = emptySet(),
    /** Last id aired yesterday, so today never opens with it. */
    val yesterdayLastId: String? = null,
)

/**
 * Packs a pool into back-to-back blocks covering one 24h day. Port of `packDay`
 * (scripts/nostalgex-daily-manifest.js / tvOS DailyManifestScheduler).
 */
class DayPacker {
    fun pack(req: DayPackRequest): List<ScheduleBlock> {
        val pool = req.pool.filter { it.durationMinutes > 0 }
        val totalPoolSec = pool.sumOf { it.durationMinutes * 60L }
        if (totalPoolSec <= 0) return emptyList()

        val dayEnd = req.dayStartEpochSec + 86_400
        val ordered = unplayedOrder(pool, req).toMutableList()
        if (req.yesterdayLastId != null && ordered.size > 1 && ordered[0].id == req.yesterdayLastId) {
            ordered.add(ordered.removeAt(0))
        }

        val blocks = ArrayList<ScheduleBlock>()
        var t = req.dayStartEpochSec
        for (item in ordered) {
            if (t >= dayEnd) break
            val dur = item.durationMinutes * 60L
            blocks.add(ScheduleBlock(item, t, t + dur))
            t += dur
        }
        if (t < dayEnd) fillWithLoop(pool, req, totalPoolSec, blocks, t, dayEnd)
        return blocks
    }

    private fun unplayedOrder(pool: List<MediaItem>, req: DayPackRequest): List<MediaItem> {
        val unplayed = pool.filter { it.id !in req.yesterdayAired }
        val interleaved = SchedulePoolOrdering.interleaveByShow(unplayed, req.channelId, req.dayNumber)
        val promoted = if (req.isPremiereChannel) {
            SchedulePoolOrdering.promoteRecentlyAdded(interleaved, req.dayStartEpochSec, req.channelId)
        } else interleaved
        return SchedulePoolOrdering.groupSequelParts(promoted)
    }

    /** Loops the whole pool from a golden-ratio offset until the day is full. */
    private fun fillWithLoop(
        pool: List<MediaItem>, req: DayPackRequest, totalPoolSec: Long,
        blocks: MutableList<ScheduleBlock>, startT: Long, dayEnd: Long,
    ) {
        val full = SchedulePoolOrdering.groupSequelParts(
            SchedulePoolOrdering.interleaveByShow(pool, req.channelId, req.dayNumber + 1),
        )
        val goldenShift = (totalPoolSec * 0.6180339887).toLong()
        val offsetSec = (req.dayNumber.toLong() * goldenShift) % totalPoolSec

        var elapsed = 0L
        var cycleIndex = 0
        var offsetInItem = offsetSec
        for (i in full.indices) {
            val d = full[i].durationMinutes * 60L
            if (elapsed + d > offsetSec) { cycleIndex = i; offsetInItem = offsetSec - elapsed; break }
            elapsed += d
        }
        if (full.size > 1) {
            val lastPlayed = blocks.lastOrNull()?.item?.id ?: req.yesterdayLastId
            if (lastPlayed != null && full[cycleIndex].id == lastPlayed) {
                cycleIndex = (cycleIndex + 1) % full.size
                offsetInItem = 0
            }
        }

        var t = startT
        var idx = cycleIndex
        while (t < dayEnd) {
            val item = full[idx % full.size]
            val fullDur = item.durationMinutes * 60L
            val playSec = minOf(fullDur - offsetInItem, dayEnd - t)
            if (playSec <= 0) { idx++; offsetInItem = 0; continue }
            blocks.add(ScheduleBlock(item, t, t + playSec))
            t += playSec
            if (offsetInItem + playSec >= fullDur) { idx++; offsetInItem = 0 } else offsetInItem += playSec
        }
    }
}
