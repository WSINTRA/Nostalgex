package app.nostalgex.playback

import app.nostalgex.backend.FakeMediaBackend
import app.nostalgex.filter.ChannelLineup
import app.nostalgex.model.Channel
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.schedule.DayPacker
import app.nostalgex.schedule.InMemoryManifestStore
import app.nostalgex.schedule.ScheduleResolver
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class MutableClock(var now: Instant, private val zone: ZoneId = ZoneOffset.UTC) : Clock() {
    override fun getZone() = zone
    override fun withZone(z: ZoneId) = MutableClock(now, z)
    override fun instant() = now
}

class FakeEngine : PlayerEngine {
    override var listener: PlayerEngine.Listener? = null
    val played = mutableListOf<PlayRequest>()
    var stopped = 0
    override fun play(request: PlayRequest) { played += request }
    override fun stop() { stopped++ }
}

class PlaybackControllerTest {
    private val clock = MutableClock(Instant.parse("2026-06-15T10:20:30Z"))
    private val pool = (1..6).map { MediaItem("m$it", "Movie $it", 90 + it * 5, MediaType.MOVIE) }
    private val channel = Channel(id = 3, number = 3, name = "ONE", colorHex = "#000")
    private val other = Channel(id = 4, number = 4, name = "TWO", colorHex = "#000")
    private val lineups = listOf(ChannelLineup(channel, pool), ChannelLineup(other, pool.reversed()))
    private val engine = FakeEngine()
    private val states = mutableListOf<PlaybackState>()

    private fun controller(backend: FakeMediaBackend = FakeMediaBackend(pool)) = PlaybackController(
        backend, ScheduleResolver(DayPacker(), InMemoryManifestStore(), clock, ZoneOffset.UTC), engine, clock, maxConsecutiveFailures = 3,
    ).also { it.onState = { s -> states += s } }

    private val playing get() = assertIs<PlaybackState.Playing>(states.last())

    @Test fun `tune plays the scheduled item at its live offset`() {
        controller().tune(lineups[0])
        val req = engine.played.single()
        val now = clock.instant().epochSecond
        assertEquals((now - playing.block.startEpochSec) * 1000, req.startPositionMs)
        assertTrue(req.url.contains(playing.block.item.id))
        assertEquals(channel, playing.channel)
    }

    @Test fun `transcode that starts at the offset is not seeked`() {
        controller().tune(lineups[0])
        // retry path uses forceTranscode which startsAtOffset -> position 0
        engine.listener!!.onError(RuntimeException("boom"))
        assertEquals(0L, engine.played.last().startPositionMs)
        assertTrue(engine.played.last().url.contains("t="))
    }

    @Test fun `first error retries same item as transcode`() {
        controller().tune(lineups[0])
        val firstId = playing.block.item.id
        engine.listener!!.onError(RuntimeException("decode"))
        assertEquals(2, engine.played.size)
        assertEquals(firstId, playing.block.item.id)
    }

    @Test fun `second error on the same block skips to up next from the start`() {
        controller().tune(lineups[0])
        val first = playing.block
        engine.listener!!.onError(RuntimeException("a"))
        engine.listener!!.onError(RuntimeException("b"))
        assertEquals(first.endEpochSec, playing.block.startEpochSec)
        assertEquals(0L, engine.played.last().startPositionMs)
    }

    @Test fun `natural end advances to the next block from the beginning`() {
        controller().tune(lineups[0])
        val first = playing.block
        clock.now = Instant.ofEpochSecond(first.endEpochSec)
        engine.listener!!.onEnded()
        assertEquals(first.endEpochSec, playing.block.startEpochSec)
        assertEquals(0L, engine.played.last().startPositionMs)
    }

    @Test fun `file ending early still moves on instead of looping`() {
        controller().tune(lineups[0])
        val first = playing.block
        clock.now = clock.now.plusSeconds(60) // still inside the block
        engine.listener!!.onEnded()
        assertEquals(first.endEpochSec, playing.block.startEpochSec)
    }

    @Test fun `repeated failures stop with an error`() {
        controller().tune(lineups[0])
        repeat(8) { engine.listener!!.onError(RuntimeException("x")) }
        assertIs<PlaybackState.Failed>(states.last())
        val count = engine.played.size
        engine.listener!!.onError(RuntimeException("x"))
        assertEquals(count, engine.played.size)
    }

    @Test fun `a successful start resets the failure count`() {
        controller().tune(lineups[0])
        repeat(2) { engine.listener!!.onError(RuntimeException("x")) }
        engine.listener!!.onReady()
        repeat(2) { engine.listener!!.onError(RuntimeException("x")) }
        assertTrue(states.last() is PlaybackState.Playing)
    }

    @Test fun `channel up and down wrap around the lineup`() {
        val c = controller()
        c.tune(lineups[0])
        c.channelUp(lineups); assertEquals(other, playing.channel)
        c.channelUp(lineups); assertEquals(channel, playing.channel)
        c.channelDown(lineups); assertEquals(other, playing.channel)
    }

    @Test fun `empty pool reports no schedule`() {
        controller().tune(ChannelLineup(channel, emptyList()))
        assertIs<PlaybackState.Failed>(states.last())
        assertTrue(engine.played.isEmpty())
    }

    @Test fun `stop halts the engine and ignores late events`() {
        val c = controller()
        c.tune(lineups[0])
        c.stop()
        val n = engine.played.size
        engine.listener!!.onEnded()
        assertEquals(n, engine.played.size)
        assertEquals(PlaybackState.Idle, states.last())
        assertTrue(engine.stopped >= 1)
    }
}
