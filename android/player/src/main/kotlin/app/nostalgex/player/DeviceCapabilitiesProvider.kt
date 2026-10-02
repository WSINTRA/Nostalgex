package app.nostalgex.player

import android.media.MediaCodecList
import app.nostalgex.backend.DeviceCapabilities

/** Reads what this device can decode, so the planner never hands it a stream it cannot show. */
object DeviceCapabilitiesProvider {
    fun detect(): DeviceCapabilities = DeviceCapabilities(hevc = hasDecoder("video/hevc"))

    private fun hasDecoder(mime: String): Boolean =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
            !info.isEncoder && info.supportedTypes.any { it.equals(mime, ignoreCase = true) }
        }
}
