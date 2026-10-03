package app.nostalgex.presentation

/** Small pure formatters for the guide. */
object GuideFormat {
    /** `#RRGGBB` or `#AARRGGBB` to an opaque-by-default ARGB value; bad input falls back to [fallback]. */
    fun parseColor(hex: String, fallback: Long = 0xFFFFE500): Long {
        val h = hex.trim().removePrefix("#")
        val v = h.toLongOrNull(16) ?: return fallback
        return when (h.length) {
            6 -> 0xFF000000 or v
            8 -> v
            else -> fallback
        }
    }

    /** `40:12` under an hour, `1:30:00` from an hour up. */
    fun clock(totalSeconds: Long): String {
        val s = maxOf(0L, totalSeconds)
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%02d:%02d".format(m, sec)
    }

    /** `40:12 / 1:30:00`. Elapsed is clamped to the duration. */
    fun elapsedOfTotal(elapsedSec: Long, totalSec: Long): String =
        "${clock(minOf(maxOf(0L, elapsedSec), totalSec))} / ${clock(totalSec)}"
}
