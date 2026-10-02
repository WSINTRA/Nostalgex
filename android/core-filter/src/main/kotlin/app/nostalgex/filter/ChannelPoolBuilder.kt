package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.time.Clock
import java.time.ZonedDateTime

/** A channel together with the items it can air right now. */
data class ChannelLineup(val channel: Channel, val pool: List<MediaItem>)

/**
 * Builds the visible lineup: filters the library per channel, applies time-of-day
 * restrictions (tvOS `Channel.filteredPool`) and drops channels below `minItems`.
 */
class ChannelPoolBuilder(
    private val filter: ChannelFilter,
    private val clock: Clock = Clock.systemDefaultZone(),
) {
    fun build(library: List<MediaItem>, channels: List<Channel>): List<ChannelLineup> =
        channels.mapNotNull { ch ->
            val base = filter.pool(library, ch)
            if (base.size < ch.minItems) null else ChannelLineup(ch, applyTimeRestrictions(base, ch))
        }

    internal fun applyTimeRestrictions(pool: List<MediaItem>, channel: Channel): List<MediaItem> {
        val tr = channel.timeRestrictions ?: return pool
        val hour = ZonedDateTime.now(clock).hour
        var result = pool

        tr.blockRatings?.let { br ->
            val blocked = (br.blockBefore?.let { hour < it } ?: false) || (br.blockAfter?.let { hour >= it } ?: false)
            if (blocked) {
                val kept = result.filter { it.contentRating.orEmpty() !in br.ratings }
                if (kept.size >= 2) result = kept
            }
        }
        tr.tvOnlyBefore?.takeIf { hour < it }?.let {
            val episodes = result.filter { it.type == MediaType.EPISODE }
            if (episodes.size >= 2) result = episodes
        }
        if (tr.onlyAfterHour?.let { hour < it } == true) return emptyList()
        return result
    }
}
