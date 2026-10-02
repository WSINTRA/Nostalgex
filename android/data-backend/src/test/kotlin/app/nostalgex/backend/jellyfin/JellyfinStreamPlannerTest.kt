package app.nostalgex.backend.jellyfin

import app.nostalgex.backend.DeviceCapabilities
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import okhttp3.HttpUrl.Companion.toHttpUrl
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class JellyfinStreamPlannerTest {
    private val caps = DeviceCapabilities(hevc = true)
    private fun planner(c: DeviceCapabilities = caps) = JellyfinStreamPlanner("http://srv:8096", "tok", "dev", c)

    private fun item(
        container: String? = "mkv", v: String? = "h264", a: String? = "aac", bits: Int? = 8,
        height: Int? = 1080, bitrate: Int? = 4000, source: String? = "src1",
    ) = MediaItem("it1", "T", 100, MediaType.MOVIE, container = container, videoCodec = v, audioCodec = a,
        videoBitDepth = bits, videoHeight = height, bitrateKbps = bitrate, mediaSourceId = source)

    @Test fun `playable mkv direct plays with static stream url`() {
        val plan = planner().plan(item(), offsetSeconds = 300)
        assertTrue(plan.isDirectPlay); assertFalse(plan.startsAtOffset)
        val u = plan.url.toHttpUrl()
        assertEquals("/Videos/it1/stream", u.encodedPath)
        assertEquals("true", u.queryParameter("Static")); assertEquals("src1", u.queryParameter("MediaSourceId"))
        assertEquals("tok", u.queryParameter("api_key"))
    }

    @Test fun `mp4 and webm direct play`() {
        assertTrue(planner().plan(item(container = "mp4")).isDirectPlay)
        assertTrue(planner().plan(item(container = "webm", v = "vp9", a = "opus")).isDirectPlay)
    }

    @Test fun `unknown metadata optimistically direct plays`() {
        assertTrue(planner().plan(item(container = null, v = null, a = null, bits = null)).isDirectPlay)
    }

    @Test fun `hevc direct plays only on capable devices`() {
        assertTrue(planner().plan(item(v = "hevc")).isDirectPlay)
        assertFalse(planner(DeviceCapabilities(hevc = false)).plan(item(v = "hevc")).isDirectPlay)
    }

    @Test fun `10-bit h264 is transcoded`() = assertFalse(planner().plan(item(bits = 10)).isDirectPlay)
    @Test fun `10-bit hevc is fine`() = assertTrue(planner().plan(item(v = "hevc", bits = 10)).isDirectPlay)
    @Test fun `unsupported container is transcoded`() = assertFalse(planner().plan(item(container = "avi")).isDirectPlay)
    @Test fun `unsupported audio is transcoded`() = assertFalse(planner().plan(item(a = "truehd")).isDirectPlay)
    @Test fun `av1 is transcoded by default`() = assertFalse(planner().plan(item(v = "av1")).isDirectPlay)
    @Test fun `source above bitrate cap is transcoded`() =
        assertFalse(planner(DeviceCapabilities(hevc = true, maxBitrateKbps = 8000)).plan(item(bitrate = 20_000)).isDirectPlay)

    @Test fun `transcode is fMP4 HLS starting at the offset`() {
        val plan = planner().plan(item(container = "avi"), offsetSeconds = 90)
        assertFalse(plan.isDirectPlay); assertTrue(plan.startsAtOffset)
        val u = plan.url.toHttpUrl()
        assertEquals("/Videos/it1/master.m3u8", u.encodedPath)
        assertEquals("900000000", u.queryParameter("StartTimeTicks"))
        assertEquals("h264,hevc", u.queryParameter("VideoCodec"))
        assertEquals("aac,ac3,eac3,mp3", u.queryParameter("AudioCodec"))
        assertEquals("mp4", u.queryParameter("SegmentContainer"))
        assertEquals("dev", u.queryParameter("DeviceId")); assertEquals("tok", u.queryParameter("api_key"))
        assertEquals("src1", u.queryParameter("MediaSourceId"))
    }

    @Test fun `transcode without hevc asks for h264 only and caps width`() {
        val c = DeviceCapabilities(hevc = false, maxBitrateKbps = 8000, maxWidth = 1920)
        val u = planner(c).plan(item(container = "avi")).url.toHttpUrl()
        assertEquals("h264", u.queryParameter("VideoCodec"))
        assertEquals("8000000", u.queryParameter("VideoBitrate")); assertEquals("1920", u.queryParameter("MaxWidth"))
    }

    @Test fun `zero offset omits start time and falls back to item id for source`() {
        val u = planner().plan(item(container = "avi", source = null)).url.toHttpUrl()
        assertEquals(null, u.queryParameter("StartTimeTicks")); assertEquals("it1", u.queryParameter("MediaSourceId"))
    }

    @Test fun `forced transcode skips direct play`() {
        val plan = planner().plan(item(), offsetSeconds = 0, forceTranscode = true)
        assertFalse(plan.isDirectPlay)
        assertNotNull(plan.url)
    }
}
