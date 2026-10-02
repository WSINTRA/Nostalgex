package app.nostalgex.schedule

import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType

/**
 * Pool ordering steps, ported from SchedulePoolOrdering.swift (via the JS port).
 * Every function is pure; output must stay bit-identical to tvOS.
 */
object SchedulePoolOrdering {
    private const val PREMIERE_WINDOW_SECONDS = 7L * 86_400
    private const val PREMIERE_ANCHOR_SECONDS = 19 * 3600
    private const val PREMIERE_SPREAD_SECONDS = 5 * 3600
    private const val PREMIERE_SLOT_SECONDS = 15 * 60
    private const val MAX_CONSECUTIVE = 2
    private val SEQUEL_MARKER = Regex("""^(.*?)[\s:,-]+(?:part|pt\.?)\s*([0-9]{1,2})\s*$""", RegexOption.IGNORE_CASE)

    fun interleaveByShow(items: List<MediaItem>, seed: Int, dayNumber: Int): List<MediaItem> {
        if (items.size <= 1) return items
        val groups = LinkedHashMap<String, MutableList<MediaItem>>()
        for (item in items) {
            val key = if (item.type == MediaType.EPISODE) item.title else "movie_${item.id}"
            groups.getOrPut(key) { mutableListOf() }.add(item)
        }
        val rng = SeededRng((Math.abs(seed.toLong()) + 1 + dayNumber).toULong())
        val shuffled = groups.values.map { it.swiftShuffled(rng) }
        val ordered = shuffled.swiftShuffled(rng)

        val result = ArrayList<MediaItem>(items.size)
        val positions = IntArray(ordered.size)
        var groupIndex = 0
        var exhausted = 0
        while (exhausted < ordered.size) {
            var attempts = 0
            while (positions[groupIndex] >= ordered[groupIndex].size) {
                groupIndex = (groupIndex + 1) % ordered.size
                attempts++
                if (attempts > ordered.size) break
            }
            if (attempts > ordered.size) break
            val group = ordered[groupIndex]
            val pos = positions[groupIndex]
            val take = minOf(MAX_CONSECUTIVE, group.size - pos)
            for (i in 0 until take) result.add(group[pos + i])
            positions[groupIndex] = pos + take
            if (positions[groupIndex] >= group.size) exhausted++
            groupIndex = (groupIndex + 1) % ordered.size
        }
        return result
    }

    /** FNV-1a over the id (UTF-8) then a murmur3 finalizer, mapped to a 15-minute prime-time slot. */
    fun premiereOffset(channelId: Int, ratingKey: String): Int {
        val slots = maxOf(1, PREMIERE_SPREAD_SECONDS / PREMIERE_SLOT_SECONDS).toULong()
        var x = channelId.toLong().toULong() + 0x9E3779B97F4A7C15UL
        for (b in ratingKey.toByteArray(Charsets.UTF_8)) {
            x = (x xor (b.toInt() and 0xFF).toULong()) * 0x00000100000001B3UL
        }
        x = x xor (x shr 33)
        x *= 0xFF51AFD7ED558CCDUL
        x = x xor (x shr 33)
        return PREMIERE_ANCHOR_SECONDS + (x % slots).toInt() * PREMIERE_SLOT_SECONDS
    }

    fun promoteRecentlyAdded(
        items: List<MediaItem>, dayStartUnix: Long, channelId: Int, windowSeconds: Long = PREMIERE_WINDOW_SECONDS,
    ): List<MediaItem> {
        if (items.size <= 1) return items
        val cutoff = dayStartUnix - windowSeconds
        fun isRecent(i: MediaItem) = i.addedAtEpochSec > 0 && i.addedAtEpochSec >= cutoff
        val recent = items.filter(::isRecent)
        if (recent.isEmpty() || recent.size >= items.size) return items

        val targets = recent
            .map { it to premiereOffset(channelId, it.id) }
            .sortedWith(compareBy({ it.second }, { it.first.id }))
        val out = items.filterNot(::isRecent).toMutableList()
        for ((item, offset) in targets) {
            var insertAt = out.size
            var cumulative = 0L
            for (index in out.indices) {
                if (cumulative >= offset) { insertAt = index; break }
                cumulative += out[index].durationMinutes * 60L
            }
            out.add(insertAt, item)
        }
        return out
    }

    fun groupSequelParts(items: List<MediaItem>): List<MediaItem> {
        if (items.size <= 1) return items
        data class Mark(val index: Int, val base: String, val ordinal: Int)
        val marks = items.mapIndexedNotNull { index, it ->
            if (it.type != MediaType.MOVIE) return@mapIndexedNotNull null
            val m = SEQUEL_MARKER.find(it.title) ?: return@mapIndexedNotNull null
            val base = m.groupValues[1].lowercase().trim()
            if (base.isEmpty()) null else Mark(index, base, m.groupValues[2].toInt())
        }
        val families = marks.groupBy { it.base }.values.filter { it.size > 1 }
        if (families.isEmpty()) return items

        val pulled = HashSet<Int>()
        val insertions = HashMap<Int, List<MediaItem>>()
        for (family in families) {
            insertions[family.minOf { it.index }] = family.sortedBy { it.ordinal }.map { items[it.index] }
            family.forEach { pulled.add(it.index) }
        }
        val result = ArrayList<MediaItem>(items.size)
        for (index in items.indices) {
            val ins = insertions[index]
            if (ins != null) result.addAll(ins) else if (index !in pulled) result.add(items[index])
        }
        return result
    }
}
