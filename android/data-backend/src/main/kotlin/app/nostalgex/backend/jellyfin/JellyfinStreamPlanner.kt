package app.nostalgex.backend.jellyfin

import app.nostalgex.backend.DeviceCapabilities
import app.nostalgex.backend.StreamPlan
import app.nostalgex.model.MediaItem
import okhttp3.HttpUrl.Companion.toHttpUrl

/** Pure decision: direct-play the file if the device can, else an fMP4 HLS transcode (tvOS: buildStreamURL). */
class JellyfinStreamPlanner(
    private val baseUrl: String,
    private val accessToken: String,
    private val deviceId: String,
    private val caps: DeviceCapabilities,
) {
    fun plan(item: MediaItem, offsetSeconds: Long = 0, forceTranscode: Boolean = false): StreamPlan =
        if (!forceTranscode && canDirectPlay(item)) StreamPlan(directUrl(item), isDirectPlay = true, startsAtOffset = false)
        else StreamPlan(transcodeUrl(item, offsetSeconds), isDirectPlay = false, startsAtOffset = true)

    internal fun canDirectPlay(item: MediaItem): Boolean {
        item.container?.lowercase()?.let { c -> if (c.split(',').none { it in caps.containers }) return false }
        item.videoCodec?.lowercase()?.let { if (it !in caps.videoCodecs) return false }
        item.audioCodec?.lowercase()?.let { if (it !in caps.audioCodecs) return false }
        // 10-bit H.264 has no hardware decoder on Fire TV; HEVC Main 10 is fine.
        if (item.videoCodec.equals("h264", true) && (item.videoBitDepth ?: 8) > 8) return false
        item.bitrateKbps?.let { if (it > caps.maxBitrateKbps) return false }
        return true
    }

    private fun directUrl(item: MediaItem) = base("/Videos/${item.id}/stream")
        .addQueryParameter("Static", "true")
        .addQueryParameter("MediaSourceId", item.mediaSourceId ?: item.id)
        .addQueryParameter("api_key", accessToken)
        .build().toString()

    private fun transcodeUrl(item: MediaItem, offsetSeconds: Long): String {
        val b = base("/Videos/${item.id}/master.m3u8")
            .addQueryParameter("MediaSourceId", item.mediaSourceId ?: item.id)
            .addQueryParameter("api_key", accessToken)
            .addQueryParameter("DeviceId", deviceId)
            .addQueryParameter("VideoCodec", caps.transcodeVideoCodecs)
            .addQueryParameter("AudioCodec", "aac,ac3,eac3,mp3")
            .addQueryParameter("VideoBitrate", (caps.maxBitrateKbps * 1000L).toString())
            .addQueryParameter("MaxWidth", caps.maxWidth.toString())
            .addQueryParameter("TranscodingMaxAudioChannels", "6")
            .addQueryParameter("SegmentContainer", "mp4")
        // The transcode must START at the offset; seeking into one that began at zero never completes.
        if (offsetSeconds > 0) b.addQueryParameter("StartTimeTicks", (offsetSeconds * 10_000_000L).toString())
        return b.build().toString()
    }

    private fun base(path: String) = (baseUrl + path).toHttpUrl().newBuilder()
}
