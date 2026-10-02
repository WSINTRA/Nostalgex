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
import app.nostalgex.store.AppRoute

/** Renders the current route. Routes are plain data; screens arrive in the next tasks. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun NostalgexRoot(container: AppContainer) {
    var route: AppRoute by remember { mutableStateOf(container.startupRouter.initialRoute()) }
    MaterialTheme(colorScheme = darkColorScheme()) {
        Column(
            Modifier.fillMaxSize().background(Color.Black),
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("NOSTALGEX", color = Color(0xFFFFE500))
            when (val r = route) {
                AppRoute.Connect -> Text("Connect screen (next task)", color = Color.White)
                is AppRoute.LoadLibrary -> Text("Signed in to ${r.session.serverName} - loading (later task)", color = Color.White)
            }
            Text("${container.channelConfig.channels.size} channels bundled", color = Color.Gray)
        }
    }
}
