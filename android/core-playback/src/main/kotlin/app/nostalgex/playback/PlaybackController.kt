package app.nostalgex.playback

import app.nostalgex.backend.MediaBackend
import app.nostalgex.filter.ChannelLineup
import app.nostalgex.schedule.ScheduleResolver
import java.time.Clock

/**
 * Drives a [PlayerEngine] like live TV: tune joins the schedule mid-program, the end of a
 * program rolls into the next one from its start, and a broken stream is retried as a
 * transcode once and then skipped. All collaborators are injected.
 */
class PlaybackController(
    private val backend: MediaBackend,
    private val resolver: ScheduleResolver,
    private val engine: PlayerEngine,
    private val clock: Clock,
    private val maxConsecutiveFailures: Int = 3,
) : PlayerEngine.Listener {
    var onState: (PlaybackState) -> Unit = {}

    private var current: ChannelLineup? = null
    private var state: PlaybackState = PlaybackState.Idle
    private var failures = 0
    private var retriedBlockStart: Long? = null

    init { engine.listener = this }

    fun tune(lineup: ChannelLineup) {
        current = lineup
        failures = 0
        retriedBlockStart = null
        val np = resolver.nowPlaying(lineup.channel, lineup.pool)
        if (np == null) { publish(PlaybackState.Failed(lineup.channel, "Nothing scheduled")); return }
        start(lineup, np.block, np.upNext, np.offsetSeconds, forceTranscode = false)
    }

    fun channelUp(all: List<ChannelLineup>) = step(all, +1)
    fun channelDown(all: List<ChannelLineup>) = step(all, -1)

    fun stop() {
        current = null
        engine.stop()
        publish(PlaybackState.Idle)
    }

    private fun step(all: List<ChannelLineup>, delta: Int) {
        if (all.isEmpty()) return
        val idx = all.indexOfFirst { it.channel.id == current?.channel?.id }
        tune(all[Math.floorMod(idx + delta, all.size)])
    }

    override fun onReady() { failures = 0 }

    override fun onEnded() {
        val playing = state as? PlaybackState.Playing ?: return
        // Re-resolve against the clock; if the file ended early and the same block is still
        // "now", move to the next program instead of replaying this one.
        val np = resolver.nowPlaying(playing.channel, current?.pool.orEmpty()) ?: return fail("Nothing scheduled")
        if (np.block.startEpochSec == playing.block.startEpochSec) advanceTo(playing.upNext) else begin(np.block, np.upNext, np.offsetSeconds)
    }

    override fun onError(cause: Throwable) {
        val playing = state as? PlaybackState.Playing ?: return
        failures++
        if (failures > maxConsecutiveFailures) return fail("Playback failed: ${cause.message}")
        val lineup = current ?: return
        if (retriedBlockStart != playing.block.startEpochSec) {
            // First failure on this program: the server may handle it where the device could not.
            retriedBlockStart = playing.block.startEpochSec
            val offset = maxOf(0L, clock.instant().epochSecond - playing.block.startEpochSec)
            start(lineup, playing.block, playing.upNext, offset, forceTranscode = true)
        } else advanceTo(playing.upNext)
    }

    private fun advanceTo(next: app.nostalgex.model.ScheduleBlock?) {
        val lineup = current ?: return
        if (next == null) return fail("Nothing scheduled")
        val following = resolver.blocksInRange(lineup.channel, lineup.pool, next.endEpochSec, next.endEpochSec + 1).firstOrNull()
        begin(next, following, offsetSeconds = 0)
    }

    private fun begin(block: app.nostalgex.model.ScheduleBlock, upNext: app.nostalgex.model.ScheduleBlock?, offsetSeconds: Long) {
        val lineup = current ?: return
        start(lineup, block, upNext, offsetSeconds, forceTranscode = false)
    }

    private fun start(
        lineup: ChannelLineup, block: app.nostalgex.model.ScheduleBlock, upNext: app.nostalgex.model.ScheduleBlock?,
        offsetSeconds: Long, forceTranscode: Boolean,
    ) {
        val plan = backend.streamPlan(block.item, offsetSeconds, forceTranscode)
        // A transcode that starts at the offset must not be seeked again: that never completes.
        val position = if (plan.startsAtOffset) 0L else offsetSeconds * 1000
        publish(PlaybackState.Playing(lineup.channel, block, upNext))
        engine.play(PlayRequest(plan.url, backend.authHeaders, position))
    }

    private fun fail(reason: String) {
        engine.stop()
        publish(PlaybackState.Failed(current?.channel, reason))
    }

    private fun publish(s: PlaybackState) { state = s; onState(s) }
}
