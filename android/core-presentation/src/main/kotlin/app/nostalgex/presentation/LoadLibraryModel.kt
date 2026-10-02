package app.nostalgex.presentation

import app.nostalgex.backend.LoadProgress
import app.nostalgex.backend.MediaBackend
import app.nostalgex.backend.jellyfin.SignInError
import app.nostalgex.filter.ChannelLineup
import app.nostalgex.filter.ChannelPoolBuilder
import app.nostalgex.model.ChannelConfig
import app.nostalgex.model.MediaItem
import app.nostalgex.store.LibrarySnapshot
import app.nostalgex.store.LibrarySnapshotStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Clock

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
) {
    private val _state = MutableStateFlow<LoadStatus>(LoadStatus.Loading("Starting..."))
    val state: StateFlow<LoadStatus> = _state.asStateFlow()

    /** Test hook: sees every published status. */
    var onProgress: (LoadStatus) -> Unit = {}

    suspend fun load(forceRescan: Boolean = false) {
        publish(LoadStatus.Loading("Checking saved library..."))
        val now = clock.instant().epochSecond
        val saved = snapshots.load(backend.serverId)
        if (saved != null && !forceRescan && now - saved.savedAtEpochSec <= maxSnapshotAgeSec) {
            publish(build(saved.items)); return
        }
        val items = try {
            scan(now)
        } catch (e: CancellationException) {
            throw e
        } catch (e: SignInError.BadCredentials) {
            publish(LoadStatus.Failed("Your sign-in expired. Please sign in again.", needsSignIn = true)); return
        } catch (e: Exception) {
            if (saved != null) { publish(build(saved.items)); return } // stale beats nothing
            publish(LoadStatus.Failed("Could not load your library: ${e.message ?: e::class.simpleName}")); return
        }
        publish(build(items))
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

    private fun build(items: List<MediaItem>): LoadStatus {
        if (items.isEmpty()) return LoadStatus.Failed("Your Jellyfin library is empty. Add movies or shows, then retry.")
        val lineups = poolBuilder.build(items, config.channels).sortedBy { it.channel.number }
        if (lineups.isEmpty()) return LoadStatus.Failed("No channel has enough matching titles yet. Your library may be too small.")
        return LoadStatus.Ready(lineups, items.size)
    }

    private fun publish(s: LoadStatus) { _state.value = s; onProgress(s) }
}
