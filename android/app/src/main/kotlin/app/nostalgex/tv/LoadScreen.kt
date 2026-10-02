package app.nostalgex.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.width
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import app.nostalgex.presentation.LoadLibraryModel
import app.nostalgex.presentation.LoadStatus
import kotlinx.coroutines.launch

/** Shows scan progress, then hands the finished lineup to [onReady]. Failures offer Retry and Sign out. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun LoadScreen(model: LoadLibraryModel, onReady: (LoadStatus.Ready) -> Unit, onSignOut: () -> Unit) {
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }

    LaunchedEffect(model) { model.load() }
    LaunchedEffect(state) { (state as? LoadStatus.Ready)?.let(onReady) }
    LaunchedEffect(state is LoadStatus.Failed) { if (state is LoadStatus.Failed) runCatching { focus.requestFocus() } }

    Column(
        Modifier.fillMaxSize().background(Color.Black).padding(horizontal = 160.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
    ) {
        Text("NOSTALGEX", color = Color(0xFFFFE500), fontSize = 40.sp)
        when (val s = state) {
            is LoadStatus.Loading -> {
                Text(s.message, color = Color.White, fontSize = 22.sp)
                if (s.itemsSoFar > 0) Text("${s.itemsSoFar} titles found", color = Color.Gray, fontSize = 16.sp)
                Bar(s.fraction)
            }
            is LoadStatus.Ready -> Text("${s.lineups.size} channels ready", color = Color.White, fontSize = 22.sp)
            is LoadStatus.Failed -> {
                Text(s.message, color = Color(0xFFFF6B6B), fontSize = 20.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (s.needsSignIn) {
                        Button(onClick = onSignOut, modifier = Modifier.focusRequester(focus)) { Text("Sign in again") }
                    } else {
                        Button(onClick = { scope.launch { model.load(forceRescan = true) } }, modifier = Modifier.focusRequester(focus)) { Text("Retry") }
                        Button(onClick = onSignOut) { Text("Sign out") }
                    }
                }
            }
        }
    }
}

@Composable
private fun Bar(fraction: Float?) {
    Row(Modifier.fillMaxWidth().height(6.dp).background(Color.DarkGray)) {
        // Indeterminate scans show a small fixed segment rather than a misleading percentage.
        Row(Modifier.fillMaxWidth(fraction?.coerceIn(0.03f, 1f) ?: 0.15f).height(6.dp).background(Color(0xFFFFE500))) {}
    }
}
