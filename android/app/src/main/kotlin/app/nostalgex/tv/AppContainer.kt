package app.nostalgex.tv

import android.content.Context
import app.nostalgex.config.ChannelConfigParser
import app.nostalgex.datastore.SharedPreferencesKeyValueStore
import app.nostalgex.model.ChannelConfig
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

    val snapshotStore: LibrarySnapshotStore by lazy { FileLibrarySnapshotStore(File(context.filesDir, "snapshots")) }
    val manifestStore: FileManifestStore by lazy { FileManifestStore(File(context.filesDir, "manifests")) }

    /** Bundled copy of the repo-root channels.json (see the Gradle copy task in :app). */
    val channelConfig: ChannelConfig by lazy {
        ChannelConfigParser().parse(context.assets.open("channels.json").bufferedReader().use { it.readText() })
    }
}
