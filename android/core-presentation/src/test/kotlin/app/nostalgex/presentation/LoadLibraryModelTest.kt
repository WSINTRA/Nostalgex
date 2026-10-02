package app.nostalgex.presentation

import app.nostalgex.backend.FakeMediaBackend
import app.nostalgex.backend.jellyfin.SignInError
import app.nostalgex.filter.ChannelFilter
import app.nostalgex.filter.ChannelPoolBuilder
import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelConfig
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.store.InMemoryLibrarySnapshotStore
import app.nostalgex.store.LibrarySnapshot
import kotlinx.coroutines.test.runTest
import java.io.IOException
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class LoadLibraryModelTest {
    private val now = Instant.parse("2026-06-15T12:00:00Z")
    private val clock = Clock.fixed(now, ZoneOffset.UTC)
    private val items = (1..4).map { MediaItem("m$it", "Movie $it", 90, MediaType.MOVIE) }
    private val snapshots = InMemoryLibrarySnapshotStore()
    private val config = ChannelConfig(
        1,
        listOf(
            Channel(2, 2, "TWO", "#000", rules = ChannelRules(), minItems = 3),
            Channel(1, 1, "ONE", "#000", rules = ChannelRules(), minItems = 3),
            Channel(3, 3, "BIG", "#000", rules = ChannelRules(), minItems = 99),
        ),
        emptyList(), emptyList(),
    )

    private fun model(backend: FakeMediaBackend) =
        LoadLibraryModel(backend, snapshots, config, ChannelPoolBuilder(ChannelFilter(clock = clock), clock), clock, maxSnapshotAgeSec = 3600)

    private val ready get() = { m: LoadLibraryModel -> assertIs<LoadStatus.Ready>(m.state.value) }

    @Test fun `starts in loading`() = assertIs<LoadStatus.Loading>(model(FakeMediaBackend(items)).state.value)

    @Test fun `cold start scans, saves a snapshot and builds the lineup sorted by channel number`() = runTest {
        val m = model(FakeMediaBackend(items))
        m.load()
        val r = ready(m)
        assertEquals(listOf(1, 2), r.lineups.map { it.channel.number })
        assertEquals(4, r.itemCount)
        assertEquals(items, snapshots.load("fake")!!.items)
    }

    @Test fun `fresh snapshot is used without scanning`() = runTest {
        snapshots.save(LibrarySnapshot("fake", now.epochSecond - 60, items))
        val m = model(FakeMediaBackend(emptyList(), failure = IOException("must not scan")))
        m.load()
        assertEquals(4, ready(m).itemCount)
    }

    @Test fun `stale snapshot triggers a rescan`() = runTest {
        snapshots.save(LibrarySnapshot("fake", now.epochSecond - 7200, items.take(1)))
        val m = model(FakeMediaBackend(items))
        m.load()
        assertEquals(4, ready(m).itemCount)
        assertEquals(now.epochSecond, snapshots.load("fake")!!.savedAtEpochSec)
    }

    @Test fun `forced rescan ignores a fresh snapshot`() = runTest {
        snapshots.save(LibrarySnapshot("fake", now.epochSecond, items.take(1)))
        val m = model(FakeMediaBackend(items))
        m.load(forceRescan = true)
        assertEquals(4, ready(m).itemCount)
    }

    @Test fun `scan failure falls back to a stale snapshot`() = runTest {
        snapshots.save(LibrarySnapshot("fake", now.epochSecond - 7200, items))
        val m = model(FakeMediaBackend(failure = IOException("offline")))
        m.load()
        assertEquals(4, ready(m).itemCount)
    }

    @Test fun `scan failure with no snapshot fails with a message`() = runTest {
        val m = model(FakeMediaBackend(failure = IOException("offline")))
        m.load()
        val f = assertIs<LoadStatus.Failed>(m.state.value)
        assertTrue(!f.needsSignIn); assertTrue(f.message.isNotBlank())
    }

    @Test fun `rejected token asks for sign in even if a snapshot exists`() = runTest {
        snapshots.save(LibrarySnapshot("fake", now.epochSecond - 7200, items))
        val m = model(FakeMediaBackend(failure = SignInError.BadCredentials()))
        m.load()
        assertTrue(assertIs<LoadStatus.Failed>(m.state.value).needsSignIn)
    }

    @Test fun `empty library is a clear failure`() = runTest {
        val m = model(FakeMediaBackend(emptyList()))
        m.load()
        assertTrue(assertIs<LoadStatus.Failed>(m.state.value).message.contains("empty", ignoreCase = true))
    }

    @Test fun `no channel reaching its minimum is a clear failure`() = runTest {
        val m = model(FakeMediaBackend(items.take(2)))
        m.load()
        assertTrue(assertIs<LoadStatus.Failed>(m.state.value).message.contains("channel", ignoreCase = true))
    }

    @Test fun `progress is surfaced while scanning`() = runTest {
        val seen = mutableListOf<LoadStatus>()
        val m = model(FakeMediaBackend(items))
        m.onProgress = { seen += it }
        m.load()
        assertTrue(seen.any { it is LoadStatus.Loading && it.itemsSoFar == 4 })
    }
}
