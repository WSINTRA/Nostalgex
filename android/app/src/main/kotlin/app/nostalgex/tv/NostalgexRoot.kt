package app.nostalgex.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import androidx.tv.material3.darkColorScheme
import app.nostalgex.presentation.LoadStatus
import app.nostalgex.store.AppRoute

/** Renders the current route. Routes are plain data; screens arrive in the next tasks. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun NostalgexRoot(container: AppContainer) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var route: AppRoute by remember { mutableStateOf(container.startupRouter.initialRoute()) }
    MaterialTheme(colorScheme = darkColorScheme()) {
        when (val r = route) {
            AppRoute.Connect -> {
                val model = remember { container.newConnectModel() }
                ConnectScreen(model) { route = AppRoute.LoadLibrary(it) }
            }
            is AppRoute.LoadLibrary -> {
                var ready by remember(r) { mutableStateOf<LoadStatus.Ready?>(null) }
                val done = ready
                if (done == null) {
                    val model = remember(r) { container.newLoadModel(r.session) }
                    LoadScreen(model, onReady = { ready = it }, onSignOut = { route = container.startupRouter.signOut() })
                } else {
                    PlaybackScreen(container, r.session, done, onExit = { (context as? android.app.Activity)?.finish() })
                }
            }
        }
    }
}
