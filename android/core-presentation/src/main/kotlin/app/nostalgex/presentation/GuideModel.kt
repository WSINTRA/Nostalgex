package app.nostalgex.presentation

import app.nostalgex.filter.ChannelLineup
import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.schedule.ScheduleResolver
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

data class GuideRow(
    val channel: Channel,
    val nowTitle: String,
    val nowStartLabel: String,
    val nowEndEpochSec: Long,
    val progress: Float,
    val nextTitle: String?,
    val nextStartLabel: String?,
    /** The program on air now, for the info panel. Null when off air. */
    val nowItem: MediaItem? = null,
    val nowStartEpochSec: Long = 0L,
    /** Channel accent colour as ARGB. */
    val colorArgb: Long = 0xFFFFE500,
    /** False for a channel with nothing scheduled right now; shown as a placeholder row. */
    val onAir: Boolean = true,
)

/** A drawn piece of a row. [title] is null for a gap. */
data class GuideCell(val title: String?, val fraction: Float, val isNow: Boolean, val isPast: Boolean)
data class GuideCells(val cells: List<GuideCell>)

/** Now/next rows for the guide. Text only and computed once per open, to stay light on old hardware. */
class GuideModel(private val resolver: ScheduleResolver, private val clock: Clock, private val zone: ZoneId) {
    private val timeFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.US).withZone(zone)

    fun rows(lineups: List<ChannelLineup>): List<GuideRow> {
        cache.clear() // now/past flags in cached cells go stale as time passes
        val now = clock.instant().epochSecond
        return lineups.map { l ->
            val np = resolver.nowPlaying(l.channel, l.pool, l.allows)
                ?: return@map GuideRow(
                    l.channel, "Off air", "", 0L, 0f, null, null,
                    colorArgb = GuideFormat.parseColor(l.channel.colorHex), onAir = false,
                )
            val b = np.block
            GuideRow(
                channel = l.channel,
                nowTitle = b.item.title,
                nowStartLabel = label(b.startEpochSec),
                nowEndEpochSec = b.endEpochSec,
                progress = if (b.durationSeconds > 0) ((now - b.startEpochSec).toFloat() / b.durationSeconds).coerceIn(0f, 1f) else 0f,
                nextTitle = np.upNext?.item?.title,
                nextStartLabel = np.upNext?.let { label(it.startEpochSec) },
                nowItem = b.item,
                nowStartEpochSec = b.startEpochSec,
                colorArgb = GuideFormat.parseColor(l.channel.colorHex),
            )
        }
    }

    /**
     * Programs of one channel inside [windowStartSec, windowStartSec + windowDurationSec) as row segments.
     * Blocks the channel may not air this hour ([ChannelLineup.allows]) are left as gaps.
     */
    fun cells(lineup: ChannelLineup, windowStartSec: Long, windowDurationSec: Long): GuideCells {
        val key = Triple(lineup.channel.id, windowStartSec, windowDurationSec)
        return cache.getOrPut(key) {
            val blocks = resolver.blocksInRange(lineup.channel, lineup.pool, windowStartSec, windowStartSec + windowDurationSec)
                .filter { lineup.allows(it.item) }
            val segments = ProgramRowLayout.segments(blocks.map { it.startEpochSec to it.endEpochSec }, windowStartSec, windowDurationSec)
            val now = clock.instant().epochSecond
            GuideCells(segments.map { seg ->
                when (seg) {
                    is RowSegment.Gap -> GuideCell(null, seg.fraction, false, false)
                    is RowSegment.Block -> {
                        val b = blocks[seg.index]
                        GuideCell(title(b.item), seg.fraction, b.contains(now), b.endEpochSec <= now)
                    }
                }
            })
        }
    }

    private val cache = HashMap<Triple<Int, Long, Long>, GuideCells>()

    /** Episodes read "Show: Episode", like tvOS. */
    private fun title(item: MediaItem) =
        if (item.type == app.nostalgex.model.MediaType.EPISODE && !item.episodeTitle.isNullOrBlank()) "${item.title}: ${item.episodeTitle}" else item.title
    fun timeLabel(epochSec: Long): String = label(epochSec)
    private fun label(epochSec: Long) = timeFormat.format(Instant.ofEpochSecond(epochSec))

    companion object {
        /** Row to highlight when the guide opens: the channel being watched, else the first. */
        /** Start of the half-hour containing [nowSec]; the guide's first column. */
        fun snapToHalfHour(nowSec: Long): Long = Math.floorDiv(nowSec, 1800L) * 1800L

        fun indexOfChannel(rows: List<GuideRow>, channelId: Int): Int = rows.indexOfFirst { it.channel.id == channelId }.coerceAtLeast(0)
    }
}
