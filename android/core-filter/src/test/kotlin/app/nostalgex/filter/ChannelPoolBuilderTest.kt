package app.nostalgex.filter

import app.nostalgex.model.BlockRatings
import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.model.TimeRestrictions
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals

class ChannelPoolBuilderTest {
    private fun builderAt(hour: Int): ChannelPoolBuilder {
        val clock = Clock.fixed(Instant.parse("2026-06-15T%02d:30:00Z".format(hour)), ZoneOffset.UTC)
        return ChannelPoolBuilder(ChannelFilter(emptyList(), clock), clock)
    }

    private fun item(t: String, type: MediaType = MediaType.MOVIE, rating: String? = "PG") =
        MediaItem(id = t, title = t, durationMinutes = 90, type = type, contentRating = rating)

    private fun ch(id: Int = 1, min: Int = 1, tr: TimeRestrictions? = null) =
        Channel(id = id, number = id, name = "C$id", colorHex = "#000", rules = ChannelRules(), timeRestrictions = tr, minItems = min)

    private val lib = listOf(item("a"), item("b"), item("c", rating = "R"), item("d", MediaType.EPISODE))

    @Test fun `channels below minItems are dropped`() {
        val lineup = builderAt(12).build(lib, listOf(ch(1, min = 4), ch(2, min = 5)))
        assertEquals(listOf(1), lineup.map { it.channel.id })
        assertEquals(4, lineup.single().pool.size)
    }

    @Test fun `blockRatings applies before the block hour`() {
        val tr = TimeRestrictions(blockRatings = BlockRatings(listOf("R"), blockBefore = 20))
        assertEquals(3, builderAt(12).build(lib, listOf(ch(tr = tr))).single().pool.size)
        assertEquals(4, builderAt(21).build(lib, listOf(ch(tr = tr))).single().pool.size)
    }

    @Test fun `blockRatings is skipped if it would leave fewer than two items`() {
        val tr = TimeRestrictions(blockRatings = BlockRatings(listOf("PG", "R"), blockBefore = 20))
        assertEquals(4, builderAt(12).build(lib, listOf(ch(tr = tr))).single().pool.size)
    }

    @Test fun `tvOnlyBefore keeps episodes only early in the day`() {
        val tr = TimeRestrictions(tvOnlyBefore = 11)
        val lib2 = lib + item("e", MediaType.EPISODE)
        assertEquals(2, builderAt(9).build(lib2, listOf(ch(tr = tr))).single().pool.size)
        assertEquals(5, builderAt(12).build(lib2, listOf(ch(tr = tr))).single().pool.size)
    }

    @Test fun `onlyAfterHour empties the pool before the gate`() {
        val tr = TimeRestrictions(onlyAfterHour = 19)
        assertEquals(0, builderAt(12).build(lib, listOf(ch(min = 0, tr = tr))).single().pool.size)
        assertEquals(4, builderAt(20).build(lib, listOf(ch(tr = tr))).single().pool.size)
    }
}
