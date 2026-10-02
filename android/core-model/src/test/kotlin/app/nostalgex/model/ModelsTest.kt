package app.nostalgex.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ModelsTest {
    private fun item(title: String = "Alien", minutes: Int = 117) =
        MediaItem(id = "k1", title = title, durationMinutes = minutes, type = MediaType.MOVIE)

    @Test fun `title strips trailing year suffix`() {
        assertEquals("Elf", item("Elf (2003)").titleWithoutYear)
        assertEquals("Elf", item("Elf").titleWithoutYear)
        assertEquals("Blade Runner 2049", item("Blade Runner 2049").titleWithoutYear)
    }

    @Test fun `block covers start inclusive and end exclusive`() {
        val block = ScheduleBlock(item(), startEpochSec = 1_000, endEpochSec = 1_600)
        assertTrue(block.contains(1_000))
        assertTrue(block.contains(1_599))
        assertFalse(block.contains(1_600))
        assertFalse(block.contains(999))
    }

    @Test fun `block reports duration and offset into program`() {
        val block = ScheduleBlock(item(), startEpochSec = 1_000, endEpochSec = 1_600)
        assertEquals(600, block.durationSeconds)
        assertEquals(250, block.offsetAt(1_250))
        assertEquals(0, block.offsetAt(900))
    }

    @Test fun `channel defaults mirror tvOS`() {
        val ch = Channel(id = 1, number = 1, name = "X", colorHex = "#FFFFFF")
        assertEquals(50, ch.minItems)
        assertFalse(ch.isPremiereChannel)
        assertEquals(ChannelRules(), ch.rules)
    }
}
