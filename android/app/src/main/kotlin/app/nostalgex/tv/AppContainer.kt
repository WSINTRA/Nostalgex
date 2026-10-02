package app.nostalgex.tv

import android.content.Context
import app.nostalgex.config.ChannelConfigParser
import app.nostalgex.datastore.SharedPreferencesKeyValueStore
import app.nostalgex.backend.jellyfin.JellyfinAuthClient
import app.nostalgex.backend.jellyfin.JellyfinBackend
import app.nostalgex.backend.jellyfin.JellyfinSession
import app.nostalgex.filter.ChannelFilter
import app.nostalgex.filter.ChannelPoolBuilder
import app.nostalgex.player.DeviceCapabilitiesProvider
import app.nostalgex.presentation.LoadLibraryModel
import app.nostalgex.playback.PlaybackController
import app.nostalgex.playback.PlayerEngine
import app.nostalgex.schedule.DayPacker
import app.nostalgex.schedule.ScheduleResolver
import java.time.Clock
import java.time.ZoneId
import app.nostalgex.model.ChannelConfig
import app.nostalgex.presentation.ConnectModel
import app.nostalgex.presentation.SignInService
import app.nostalgex.store.DeviceIdProvider
import app.nostalgex.store.FileLibrarySnapshotStore
import app.nostalgex.store.FileManifestStore
import app.nostalgex.store.KeyValueStore
import app.nostalgex.store.LibrarySnapshotStore
import app.nostalgex.store.SessionStore
import app.nostalgex.store.StartupRouter
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Hand-written composition root: the one place concrete classes are chosen and wired.
 * Everything else receives its collaborators through constructors, so tests substitute fakes.
 */
class AppContainer(private val context: Context) {
    val keyValueStore: KeyValueStore by lazy { SharedPreferencesKeyValueStore(context) }
    val sessionStore: SessionStore by lazy { SessionStore(keyValueStore) }
    val deviceId: String by lazy { DeviceIdProvider(keyValueStore).get() }
    val startupRouter: StartupRouter by lazy { StartupRouter(sessionStore) }

    val httpClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .callTimeout(15, TimeUnit.MINUTES)
            .build()
    }

    val authClient: JellyfinAuthClient by lazy { JellyfinAuthClient(httpClient, deviceId) }

    /** A fresh model per connect screen visit. */
    fun newConnectModel() = ConnectModel(SignInService { c, u, p -> authClient.signInFirstReachable(c, u, p) }, sessionStore)

    val clock: Clock = Clock.systemDefaultZone()

    fun newBackend(session: JellyfinSession) =
        JellyfinBackend(httpClient, session, deviceId, capabilities = DeviceCapabilitiesProvider.detect())

    /** Controller for one playback session; the engine is supplied by the screen that owns the player. */
    fun newPlaybackController(session: JellyfinSession, engine: PlayerEngine) = PlaybackController(
        backend = newBackend(session),
        resolver = ScheduleResolver(DayPacker(), manifestStore, clock, ZoneId.systemDefault()),
        engine = engine,
        clock = clock,
    )

    /** A fresh load model per signed-in session. */
    fun newLoadModel(session: JellyfinSession) = LoadLibraryModel(
        backend = newBackend(session),
        snapshots = snapshotStore,
        config = channelConfig,
        poolBuilder = ChannelPoolBuilder(ChannelFilter(channelConfig.exclusiveRules, clock), clock),
        clock = clock,
    )

    val snapshotStore: LibrarySnapshotStore by lazy { FileLibrarySnapshotStore(File(context.filesDir, "snapshots")) }
    val manifestStore: FileManifestStore by lazy { FileManifestStore(File(context.filesDir, "manifests")) }

    /** Bundled copy of the repo-root channels.json (see the Gradle copy task in :app). */
    val channelConfig: ChannelConfig by lazy {
        ChannelConfigParser().parse(context.assets.open("channels.json").bufferedReader().use { it.readText() })
    }
}
