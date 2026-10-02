package app.nostalgex.config

import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChannelConfigParserTest {
    private val parser = ChannelConfigParser()

    private fun config(channel: String, extra: String = "") =
        """{"version":3,$extra"channels":[$channel]}"""

    @Test fun `minimal channel gets tvOS defaults`() {
        val ch = parser.parse(config("""{"id":1,"number":2,"name":"A","colorHex":"#FFE500"}""")).channels.single()
        assertEquals(1, ch.id)
        assertEquals(2, ch.number)
        assertEquals(50, ch.minItems)
        assertEquals(false, ch.isPremiereChannel)
        assertNull(ch.rules.type)
    }

    @Test fun `rule fields map across`() {
        val json = config(
            """{"id":1,"number":1,"name":"A","colorHex":"#000","minItems":5,"isPremiereChannel":true,
            "rules":{"type":"movie","source":"musicVideo","genres":{"include":["Comedy"],"exclude":["Horror"]},
            "yearRange":{"min":1980,"max":1999},"durationRange":{"max":100},"contentRatings":["PG"],
            "allowUnrated":true,"ratingMin":6.5,"rewatched":true,"titleContains":["x"],"keywords":["k"]}}"""
        )
        val ch = parser.parse(json).channels.single()
        val r = ch.rules
        assertEquals(5, ch.minItems)
        assertTrue(ch.isPremiereChannel)
        assertEquals(MediaType.MOVIE, r.type)
        assertEquals(LibrarySource.MUSIC_VIDEO, r.source)
        assertEquals(listOf("Comedy"), r.genres?.include)
        assertEquals(listOf("Horror"), r.genres?.exclude)
        assertEquals(emptyList(), r.genres?.requireAll)
        assertEquals(1980, r.yearRange?.min)
        assertEquals(100, r.durationRange?.max)
        assertNull(r.durationRange?.min)
        assertTrue(r.allowUnrated)
        assertEquals(6.5, r.ratingMin)
        assertTrue(r.rewatched)
        assertEquals(listOf("k"), r.keywords)
    }

    @Test fun `episode type and tv source`() {
        val ch = parser.parse(config("""{"id":1,"number":1,"name":"A","colorHex":"#000","rules":{"type":"episode","source":"tv"}}""")).channels.single()
        assertEquals(MediaType.EPISODE, ch.rules.type)
        assertEquals(LibrarySource.TV, ch.rules.source)
    }

    @Test fun `time restrictions map across`() {
        val ch = parser.parse(
            config("""{"id":1,"number":1,"name":"A","colorHex":"#000","timeRestrictions":{"blockRatings":{"ratings":["R"],"blockBefore":20},"tvOnlyBefore":11,"onlyAfterHour":19}}""")
        ).channels.single()
        val tr = assertNotNull(ch.timeRestrictions)
        assertEquals(listOf("R"), tr.blockRatings?.ratings)
        assertEquals(20, tr.blockRatings?.blockBefore)
        assertNull(tr.blockRatings?.blockAfter)
        assertEquals(11, tr.tvOnlyBefore)
        assertEquals(19, tr.onlyAfterHour)
    }

    @Test fun `bundles and exclusive rules including legacy single channelID`() {
        val json = config(
            """{"id":1,"number":1,"name":"A","colorHex":"#000"}""",
            extra = """"bundles":[{"id":"b","name":"B","channelIDs":[1,2],"activeMonths":[10,11]}],
            "exclusiveRules":[{"channelID":7,"genres":["Anime"]},{"channelIDs":[1,2],"editorialTitles":["Elf"],"manifestExclusive":true}],"""
        )
        val cfg = parser.parse(json)
        assertEquals(listOf(1, 2), cfg.bundles.single().channelIds)
        assertEquals(listOf(10, 11), cfg.bundles.single().activeMonths)
        assertNull(cfg.bundles.single().description)
        assertEquals(listOf(7), cfg.exclusiveRules[0].channelIds)
        assertEquals(listOf("Anime"), cfg.exclusiveRules[0].genres)
        assertEquals(listOf(1, 2), cfg.exclusiveRules[1].channelIds)
        assertTrue(cfg.exclusiveRules[1].manifestExclusive)
    }

    @Test fun `unknown keys are ignored`() {
        val cfg = parser.parse(config("""{"id":1,"number":1,"name":"A","colorHex":"#000","futureField":1,"rules":{"nope":true}}"""))
        assertEquals(1, cfg.channels.size)
    }

    @Test fun `malformed json raises ConfigParseException`() {
        assertFailsWith<ConfigParseException> { parser.parse("not json") }
        assertFailsWith<ConfigParseException> { parser.parse("""{"version":1}""") }
    }

    @Test fun `repo channels json parses`() {
        val text = checkNotNull(javaClass.classLoader.getResource("channels.json")) { "channels.json not copied" }.readText()
        val cfg = parser.parse(text)
        assertTrue(cfg.channels.size > 100)
        assertTrue(cfg.bundles.isNotEmpty())
        assertEquals(cfg.channels.size, cfg.channels.map { it.id }.toSet().size, "channel ids must be unique")
        val bundled = cfg.bundles.flatMap { it.channelIds }.toSet()
        val known = cfg.channels.map { it.id }.toSet()
        assertTrue(known.containsAll(bundled), "bundle references unknown channels: ${bundled - known}")
        assertEquals(1, cfg.channels.count { it.isPremiereChannel })
    }
}
