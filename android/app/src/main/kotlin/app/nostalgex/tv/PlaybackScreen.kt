package app.nostalgex.tv

import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
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
import app.nostalgex.presentation.OsdInfo
import app.nostalgex.presentation.OsdModel
import app.nostalgex.presentation.OsdVisibility
import kotlinx.coroutines.delay

/**
 * Full-screen live TV. D-pad Up/Down change channel (wrapping), OK shows the info banner,
 * which also appears on every tune and hides after a few seconds.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlaybackScreen(container: AppContainer, session: JellyfinSession, ready: LoadStatus.Ready, onExit: () -> Unit) {
    val context = LocalContext.current
    var state by remember { mutableStateOf<PlaybackState>(PlaybackState.Idle) }
    var nowSec by remember { mutableLongStateOf(container.clock.instant().epochSecond) }
    val osd = remember { OsdVisibility(hideAfterSec = 5) }
    val engine = remember { Media3PlayerEngine(context) }
    val controller = remember {
        container.newPlaybackController(session, engine).also {
            it.onState = { s ->
                state = s
                if (s is PlaybackState.Playing) osd.show(container.clock.instant().epochSecond)
            }
        }
    }
    val focus = remember { FocusRequester() }

    DisposableEffect(Unit) {
        controller.tune(ready.lineups.first())
        onDispose { controller.stop(); engine.release() }
    }
    // Tick once a second so the banner's countdown and auto-hide stay current.
    LaunchedEffect(Unit) {
        while (true) { nowSec = container.clock.instant().epochSecond; delay(1000) }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
    BackHandler(onBack = onExit)

    val info = OsdModel.describe(state, nowSec)

    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionUp, Key.ChannelUp -> { controller.channelUp(ready.lineups); true }
                    Key.DirectionDown, Key.ChannelDown -> { controller.channelDown(ready.lineups); true }
                    Key.DirectionCenter, Key.Enter, Key.NumPadEnter -> { osd.show(container.clock.instant().epochSecond); true }
                    else -> false
                }
            },
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    useController = false
                    isFocusable = false
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    player = engine.player
                }
            },
        )
        (state as? PlaybackState.Failed)?.let {
            Text(it.reason, color = Color(0xFFFF6B6B), fontSize = 20.sp, modifier = Modifier.align(Alignment.Center))
        }
        if (info != null && osd.isVisible(nowSec)) Banner(info, Modifier.align(Alignment.BottomStart))
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun Banner(info: OsdInfo, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().background(Color(0xCC000000)).padding(horizontal = 48.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(info.channelLabel, color = Color(0xFFFFE500), fontSize = 22.sp)
        Text(info.title, color = Color.White, fontSize = 28.sp)
        info.subtitle?.let { Text(it, color = Color.LightGray, fontSize = 18.sp) }
        Text(
            buildString {
                append(info.remainingLabel)
                info.upNextTitle?.let { append("   |   Up next: ").append(it) }
            },
            color = Color.Gray, fontSize = 16.sp,
        )
    }
}
