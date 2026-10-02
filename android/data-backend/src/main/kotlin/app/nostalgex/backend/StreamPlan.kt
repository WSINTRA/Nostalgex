package app.nostalgex.backend

/**
 * What this device can play. Injected so the planner is testable and so Android code
 * can fill it from MediaCodecList without the backend depending on Android.
 */
data class DeviceCapabilities(
    val hevc: Boolean,
    val containers: Set<String> = setOf("mp4", "m4v", "mov", "mkv", "matroska", "webm"),
    val audioCodecs: Set<String> = setOf("aac", "ac3", "eac3", "mp3", "opus", "vorbis", "flac"),
    val maxBitrateKbps: Int = 40_000,
    val maxWidth: Int = 1920,
) {
    val videoCodecs: Set<String> get() = buildSet { add("h264"); add("vp9"); if (hevc) add("hevc") }
    /** Codecs requested for HLS transcodes (the server re-encodes anything else to H.264). */
    val transcodeVideoCodecs: String get() = if (hevc) "h264,hevc" else "h264"
}

/** How to play an item. [startsAtOffset] true means the stream already begins at the requested offset: do not seek. */
data class StreamPlan(val url: String, val isDirectPlay: Boolean, val startsAtOffset: Boolean)
