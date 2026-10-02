package app.nostalgex.presentation

import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.model.ScheduleBlock
import app.nostalgex.playback.PlaybackState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OsdModelTest {
    private val channel = Channel(12, 12, "COMEDY", "#000")
    private fun block(title: String, start: Long, end: Long, ep: String? = null, tag: String? = null) =
        ScheduleBlock(MediaItem("id", title, 90, if (ep != null) MediaType.EPISODE else MediaType.MOVIE, episodeTitle = ep, seTag = tag), start, end)

    private val playing = PlaybackState.Playing(channel, block("Heat", 1000, 7000), block("Alien", 7000, 12000))

    @Test fun `describes channel, title, time left and up next`() {
        val info = OsdModel.describe(playing, nowSec = 4000)!!
        assertEquals("12  COMEDY", info.channelLabel)
        assertEquals("Heat", info.title)
        assertNull(info.subtitle)
        assertEquals(3000, info.remainingSeconds)
        assertEquals("Alien", info.upNextTitle)
        assertEquals("50 min left", info.remainingLabel)
    }

    @Test fun `episodes show tag and episode name`() {
        val s = playing.copy(block = block("Seinfeld", 0, 1300, ep = "The Pilot", tag = "S01E04"))
        assertEquals("S01E04  The Pilot", OsdModel.describe(s, 0)!!.subtitle)
    }

    @Test fun `remaining time is clamped and rounded up to minutes`() {
        assertEquals("1 min left", OsdModel.describe(playing, nowSec = 6990)!!.remainingLabel)
        assertEquals("0 min left", OsdModel.describe(playing, nowSec = 9000)!!.remainingLabel)
        assertEquals(0, OsdModel.describe(playing, nowSec = 9000)!!.remainingSeconds)
    }

    @Test fun `no up next is allowed`() = assertNull(OsdModel.describe(playing.copy(upNext = null), 4000)!!.upNextTitle)

    @Test fun `idle and failed have no info`() {
        assertNull(OsdModel.describe(PlaybackState.Idle, 0))
        assertNull(OsdModel.describe(PlaybackState.Failed(channel, "x"), 0))
    }

    @Test fun `visibility lasts the configured time after show`() {
        val v = OsdVisibility(hideAfterSec = 5)
        assertFalse(v.isVisible(0))
        v.show(100)
        assertTrue(v.isVisible(100)); assertTrue(v.isVisible(104)); assertFalse(v.isVisible(105))
    }

    @Test fun `showing again extends it and hide closes it`() {
        val v = OsdVisibility(5)
        v.show(0); v.show(4)
        assertTrue(v.isVisible(8))
        v.hide()
        assertFalse(v.isVisible(8))
    }
}
