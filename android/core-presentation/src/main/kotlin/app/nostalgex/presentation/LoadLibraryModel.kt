package app.nostalgex.presentation

import app.nostalgex.backend.LoadProgress
import app.nostalgex.backend.MediaBackend
import app.nostalgex.backend.jellyfin.SignInError
import app.nostalgex.filter.ChannelLineup
import app.nostalgex.filter.ChannelPoolBuilder
import app.nostalgex.model.ChannelConfig
import app.nostalgex.model.MediaItem
import app.nostalgex.store.LibrarySnapshot
import app.nostalgex.store.InMemoryLineupIndexStore
import app.nostalgex.store.LibrarySnapshotStore
import app.nostalgex.store.LineupIndex
import app.nostalgex.store.LineupIndexStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

sealed interface LoadStatus {
    data class Loading(val message: String, val itemsSoFar: Int = 0, val fraction: Float? = null) : LoadStatus
    data class Ready(val lineups: List<ChannelLineup>, val itemCount: Int) : LoadStatus
    data class Failed(val message: String, val needsSignIn: Boolean = false) : LoadStatus
}

/**
 * Loads the library (snapshot first, scan when stale) and builds the channel lineup.
 * Everything is injected, so it runs on the JVM with a fake backend and in-memory store.
 */
class LoadLibraryModel(
    private val backend: MediaBackend,
    private val snapshots: LibrarySnapshotStore,
    private val config: ChannelConfig,
    private val poolBuilder: ChannelPoolBuilder,
    private val clock: Clock,
    private val maxSnapshotAgeSec: Long = 6 * 3600,
    private val lineupIndex: LineupIndexStore = InMemoryLineupIndexStore(),
    /** Identifies the channel rules (e.g. a hash of channels.json); a change invalidates the cached lineup. */
    private val configKey: String = "",
) {
    private val _state = MutableStateFlow<LoadStatus>(LoadStatus.Loading("Starting..."))
    val state: StateFlow<LoadStatus> = _state.asStateFlow()

    /** Test hook: sees every published status. */
    var onProgress: (LoadStatus) -> Unit = {}

    /** Runs off the caller's thread: snapshot I/O, JSON and channel filtering are heavy on a Fire Stick. */
    suspend fun load(forceRescan: Boolean = false) = withContext(Dispatchers.Default) { doLoad(forceRescan) }

    private suspend fun doLoad(forceRescan: Boolean) {
        publish(LoadStatus.Loading("Checking saved library..."))
        val now = clock.instant().epochSecond
        val saved = snapshots.load(backend.serverId)
        if (saved != null && !forceRescan && now - saved.savedAtEpochSec <= maxSnapshotAgeSec) {
            publish(build(saved.items, saved.savedAtEpochSec)); return
        }
        val items = try {
            scan(now)
        } catch (e: CancellationException) {
            throw e
        } catch (e: SignInError.BadCredentials) {
            publish(LoadStatus.Failed("Your sign-in expired. Please sign in again.", needsSignIn = true)); return
        } catch (e: Exception) {
            if (saved != null) { publish(build(saved.items, saved.savedAtEpochSec)); return } // stale beats nothing
            publish(LoadStatus.Failed("Could not load your library: ${e.message ?: e::class.simpleName}")); return
        } catch (e: OutOfMemoryError) {
            publish(LoadStatus.Failed("Your library is too large for this device's memory.")); return
        }
        // A scan that succeeds but finds nothing must not hide a usable saved library.
        if (items.isEmpty() && saved != null) { publish(build(saved.items, saved.savedAtEpochSec)); return }
        publish(build(items, now))
    }

    private suspend fun scan(now: Long): List<MediaItem> {
        val items = backend.loadLibrary { p -> publish(progress(p)) }
        if (items.isNotEmpty()) snapshots.save(LibrarySnapshot(backend.serverId, now, items))
        return items
    }

    private fun progress(p: LoadProgress) = LoadStatus.Loading(
        message = "Scanning ${p.sectionTitle} (${p.sectionIndex + 1} of ${p.totalSections})",
        itemsSoFar = p.itemsLoadedSoFar,
        fraction = if (p.totalSections > 0) p.sectionIndex.toFloat() / p.totalSections else null,
    )

    /** [savedAt] identifies the library version, so the cached lineup is reused only for the same snapshot. */
    private fun build(items: List<MediaItem>, savedAt: Long): LoadStatus {
        publish(LoadStatus.Loading("Building channels...", items.size, 0f))
        if (items.isEmpty()) return LoadStatus.Failed("Your Jellyfin library is empty. Add movies or shows, then retry.")
        // Filters also depend on today's date (recency rules), so the key includes it.
        val key = "$savedAt:${items.size}:$configKey:${LocalDate.now(clock.withZone(ZoneId.systemDefault()))}"
        val cached = lineupIndex.load(backend.serverId)?.takeIf { it.key == key }
            ?.let { poolBuilder.fromIds(items, config.channels, it.channelItemIds) }
        val lineups = (cached ?: freshLineups(items, key)).sortedBy { it.channel.number }
        if (lineups.isEmpty()) return LoadStatus.Failed("No channel has enough matching titles yet. Your library may be too small.")
        return LoadStatus.Ready(lineups, items.size)
    }

    private fun freshLineups(items: List<MediaItem>, key: String): List<ChannelLineup> {
        var last = 0
        val lineups = poolBuilder.build(items, config.channels) { done, total ->
            // Throttled: publishing per channel would flood the UI thread on a slow stick.
            if (done == total || done - last >= 5) {
                last = done
                publish(LoadStatus.Loading("Building channels ($done of $total)", items.size, done.toFloat() / total))
            }
        }
        if (lineups.isNotEmpty()) {
            try { lineupIndex.save(backend.serverId, LineupIndex(key, lineups.associate { it.channel.id to it.pool.map { m -> m.id } })) }
            catch (e: java.io.IOException) { /* cache is an optimisation only */ }
        }
        return lineups
    }

    private fun publish(s: LoadStatus) { _state.value = s; onProgress(s) }
}
