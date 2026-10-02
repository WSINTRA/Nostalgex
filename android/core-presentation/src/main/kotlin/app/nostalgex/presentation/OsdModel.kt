package app.nostalgex.presentation

import app.nostalgex.playback.PlaybackState

data class OsdInfo(
    val channelLabel: String,
    val title: String,
    val subtitle: String?,
    val remainingSeconds: Long,
    val upNextTitle: String?,
) {
    /** Whole minutes, rounded up, so the last seconds still read "1 min left". */
    val remainingLabel: String get() = "${(remainingSeconds + 59) / 60} min left"
}

/** What the on-screen display shows for a playback state. Pure. */
object OsdModel {
    fun describe(state: PlaybackState, nowSec: Long): OsdInfo? {
        val p = state as? PlaybackState.Playing ?: return null
        val item = p.block.item
        val subtitle = listOfNotNull(item.seTag, item.episodeTitle).joinToString("  ").ifEmpty { null }
        return OsdInfo(
            channelLabel = "${p.channel.number}  ${p.channel.name}",
            title = item.title,
            subtitle = subtitle,
            remainingSeconds = maxOf(0L, p.block.endEpochSec - nowSec),
            upNextTitle = p.upNext?.item?.title,
        )
    }
}

/** Time-boxed visibility of the OSD. The caller passes the current time, so it is deterministic. */
class OsdVisibility(private val hideAfterSec: Long = 5) {
    private var shownUntil: Long = Long.MIN_VALUE

    fun show(nowSec: Long) { shownUntil = nowSec + hideAfterSec }
    fun hide() { shownUntil = Long.MIN_VALUE }
    fun isVisible(nowSec: Long): Boolean = nowSec < shownUntil
}
