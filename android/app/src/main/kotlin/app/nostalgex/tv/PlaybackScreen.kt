package app.nostalgex.tv

import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import app.nostalgex.backend.jellyfin.JellyfinSession
import app.nostalgex.player.Media3PlayerEngine
import app.nostalgex.playback.PlaybackState
import app.nostalgex.presentation.LoadStatus

/**
 * Full-screen live TV. Tunes the first channel at its live offset; the controller handles
 * auto-advance and retries. Channel changing and the on-screen display come in Task 21.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlaybackScreen(container: AppContainer, session: JellyfinSession, ready: LoadStatus.Ready, onExit: () -> Unit) {
    val context = LocalContext.current
    var state by remember { mutableStateOf<PlaybackState>(PlaybackState.Idle) }
    val engine = remember { Media3PlayerEngine(context) }
    val controller = remember { container.newPlaybackController(session, engine).also { it.onState = { s -> state = s } } }

    DisposableEffect(Unit) {
        controller.tune(ready.lineups.first())
        onDispose { controller.stop(); engine.release() }
    }
    BackHandler(onBack = onExit)

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    useController = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    player = engine.player
                }
            },
        )
        Column(Modifier.align(Alignment.BottomStart).padding(48.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            when (val s = state) {
                is PlaybackState.Playing -> {
                    Text("${s.channel.number}  ${s.channel.name}", color = Color(0xFFFFE500), fontSize = 22.sp)
                    Text(s.block.item.title, color = Color.White, fontSize = 18.sp)
                }
                is PlaybackState.Failed -> Text(s.reason, color = Color(0xFFFF6B6B), fontSize = 20.sp)
                PlaybackState.Idle -> Unit
            }
        }
    }
}
