package app.nostalgex.presentation

import app.nostalgex.filter.ChannelLineup
import app.nostalgex.model.Channel
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
)

/** Now/next rows for the guide. Text only and computed once per open, to stay light on old hardware. */
class GuideModel(private val resolver: ScheduleResolver, private val clock: Clock, private val zone: ZoneId) {
    private val timeFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.US).withZone(zone)

    fun rows(lineups: List<ChannelLineup>): List<GuideRow> {
        val now = clock.instant().epochSecond
        return lineups.mapNotNull { l ->
            val np = resolver.nowPlaying(l.channel, l.pool) ?: return@mapNotNull null
            val b = np.block
            GuideRow(
                channel = l.channel,
                nowTitle = title(b.item),
                nowStartLabel = label(b.startEpochSec),
                nowEndEpochSec = b.endEpochSec,
                progress = if (b.durationSeconds > 0) ((now - b.startEpochSec).toFloat() / b.durationSeconds).coerceIn(0f, 1f) else 0f,
                nextTitle = np.upNext?.let { title(it.item) },
                nextStartLabel = np.upNext?.let { label(it.startEpochSec) },
            )
        }
    }

    private fun title(item: app.nostalgex.model.MediaItem) = item.title
    private fun label(epochSec: Long) = timeFormat.format(Instant.ofEpochSecond(epochSec))

    companion object {
        /** Row to highlight when the guide opens: the channel being watched, else the first. */
        fun indexOfChannel(rows: List<GuideRow>, channelId: Int): Int = rows.indexOfFirst { it.channel.id == channelId }.coerceAtLeast(0)
    }
}
