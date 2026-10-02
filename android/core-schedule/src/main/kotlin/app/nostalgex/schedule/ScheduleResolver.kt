package app.nostalgex.schedule

import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.ScheduleBlock
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

data class NowPlaying(val block: ScheduleBlock, val offsetSeconds: Long, val upNext: ScheduleBlock?)

/** Answers "what is on channel X now / in this window" using persisted daily manifests. */
class ScheduleResolver(
    private val packer: DayPacker,
    private val store: ManifestStore,
    private val clock: Clock,
    private val zone: ZoneId,
) {
    fun nowPlaying(channel: Channel, pool: List<MediaItem>): NowPlaying? {
        val now = clock.instant().epochSecond
        val today = LocalDate.now(clock.withZone(zone))
        val blocks = blocksForDay(channel, pool, today)
        val idx = blocks.indexOfFirst { it.contains(now) }
        if (idx < 0) return null
        val block = blocks[idx]
        val upNext = blocks.getOrNull(idx + 1) ?: blocksForDay(channel, pool, today.plusDays(1)).firstOrNull()
        return NowPlaying(block, block.offsetAt(now), upNext)
    }

    fun blocksInRange(channel: Channel, pool: List<MediaItem>, fromSec: Long, toSec: Long): List<ScheduleBlock> {
        var day = java.time.Instant.ofEpochSecond(fromSec).atZone(zone).toLocalDate()
        val last = java.time.Instant.ofEpochSecond(toSec).atZone(zone).toLocalDate()
        val out = ArrayList<ScheduleBlock>()
        while (!day.isAfter(last)) {
            out += blocksForDay(channel, pool, day).filter { it.endEpochSec > fromSec && it.startEpochSec < toSec }
            day = day.plusDays(1)
        }
        return out
    }

    fun blocksForDay(channel: Channel, pool: List<MediaItem>, day: LocalDate): List<ScheduleBlock> {
        val valid = pool.filter { it.durationMinutes > 0 }
        if (valid.isEmpty()) return emptyList()
        val key = day.toString()
        val fingerprint = fingerprint(valid)
        val byId = valid.associateBy { it.id }

        store.load(channel.id, key)?.takeIf { it.poolFingerprint == fingerprint }?.let { cached ->
            return cached.blocks.mapNotNull { b -> byId[b.id]?.let { ScheduleBlock(it, b.startEpochSec, b.endEpochSec) } }
        }

        val dayStart = day.atStartOfDay(zone).toEpochSecond()
        val yesterday = store.load(channel.id, day.minusDays(1).toString())
        val blocks = packer.pack(
            DayPackRequest(
                pool = valid,
                dayStartEpochSec = dayStart,
                dayNumber = Math.floorDiv(dayStart, 86_400L).toInt(),
                channelId = channel.id,
                isPremiereChannel = channel.isPremiereChannel,
                yesterdayAired = yesterday?.blocks?.map { it.id }?.toSet().orEmpty(),
                yesterdayLastId = yesterday?.blocks?.lastOrNull()?.id,
            ),
        )
        store.save(channel.id, StoredDay(key, fingerprint, blocks.map { StoredBlock(it.item.id, it.startEpochSec, it.endEpochSec) }))
        return blocks
    }

    private fun fingerprint(pool: List<MediaItem>): String =
        pool.map { it.id }.sorted().joinToString(",").hashCode().toString()
}
