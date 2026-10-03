package app.nostalgex.presentation

import kotlin.test.Test
import kotlin.test.assertEquals

class GuideFormatTest {
    @Test fun `parses six and eight digit hex colours`() {
        assertEquals(0xFFFA47B2, GuideFormat.parseColor("#FA47B2"))
        assertEquals(0x80112233, GuideFormat.parseColor("#80112233"))
    }

    @Test fun `bad colours fall back`() {
        assertEquals(0xFFFFE500, GuideFormat.parseColor("nope"))
        assertEquals(0xFF123456, GuideFormat.parseColor("#xyz", fallback = 0xFF123456))
        assertEquals(0xFFFFE500, GuideFormat.parseColor("#12345"))
    }

    @Test fun `clock formats minutes and hours`() {
        assertEquals("40:12", GuideFormat.clock(40 * 60 + 12))
        assertEquals("1:30:00", GuideFormat.clock(5400))
        assertEquals("00:00", GuideFormat.clock(-5))
    }

    @Test fun `elapsed of total clamps elapsed`() {
        assertEquals("40:12 / 1:30:00", GuideFormat.elapsedOfTotal(2412, 5400))
        assertEquals("1:30:00 / 1:30:00", GuideFormat.elapsedOfTotal(9999, 5400))
    }

    @Test fun `half hour snapping`() {
        assertEquals(1800L * 10, GuideModel.snapToHalfHour(1800L * 10 + 1799))
        assertEquals(1800L * 10, GuideModel.snapToHalfHour(1800L * 10))
    }
}
