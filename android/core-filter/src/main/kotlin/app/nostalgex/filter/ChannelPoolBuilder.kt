package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.time.Clock
import java.time.ZonedDateTime

/**
 * A channel with its stable base [pool]. The pool never changes with the hour, so the day's
 * schedule stays fixed; [allows] applies time-of-day restrictions live, at playback time.
 */
data class ChannelLineup(
    val channel: Channel,
    val pool: List<MediaItem>,
    val allows: (MediaItem) -> Boolean = { true },
) {
    /** Items allowed on air at this moment. */
    fun eligible(): List<MediaItem> = pool.filter(allows)
}

/**
 * Builds the visible lineup: filters the library per channel, applies time-of-day
 * restrictions (tvOS `Channel.filteredPool`) and drops channels below `minItems`.
 */
class ChannelPoolBuilder(
    private val filter: ChannelFilter,
    private val clock: Clock = Clock.systemDefaultZone(),
) {
    /** [onProgress] gets (channelsDone, totalChannels) after each channel, so a UI can show progress. */
    fun build(
        library: List<MediaItem>, channels: List<Channel>, onProgress: (Int, Int) -> Unit = { _, _ -> },
    ): List<ChannelLineup> {
        val prepared = filter.prepare(library)
        return channels.mapIndexedNotNull { i, ch ->
            val base = filter.poolPrepared(prepared, ch)
            onProgress(i + 1, channels.size)
            if (base.size < ch.minItems) null else ChannelLineup(ch, base, allowsFor(base, ch))
        }
    }

    /** Rebuilds lineups from previously computed base pools (channel id -> item ids) without filtering. */
    fun fromIds(library: List<MediaItem>, channels: List<Channel>, ids: Map<Int, List<String>>): List<ChannelLineup>? {
        val byId = library.associateBy { it.id }
        return channels.mapNotNull { ch ->
            val list = ids[ch.id] ?: return@mapNotNull null
            val base = list.map { byId[it] ?: return null } // library changed under the cache: caller refilters
            ChannelLineup(ch, base, allowsFor(base, ch))
        }
    }

    /** Predicate that re-evaluates the restrictions whenever the hour changes. */
    private fun allowsFor(base: List<MediaItem>, ch: Channel): (MediaItem) -> Boolean {
        if (ch.timeRestrictions == null) return { true }
        var cachedHour = -1
        var cachedIds: Set<String> = emptySet()
        return { item ->
            synchronized(this) {
                val hour = ZonedDateTime.now(clock).hour
                if (hour != cachedHour) {
                    cachedIds = applyTimeRestrictions(base, ch, hour).mapTo(HashSet()) { it.id }
                    cachedHour = hour
                }
                item.id in cachedIds
            }
        }
    }

    internal fun applyTimeRestrictions(
        pool: List<MediaItem>, channel: Channel, hour: Int = ZonedDateTime.now(clock).hour,
    ): List<MediaItem> {
        val tr = channel.timeRestrictions ?: return pool
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
