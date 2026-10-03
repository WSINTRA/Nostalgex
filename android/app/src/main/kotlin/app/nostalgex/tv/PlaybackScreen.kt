package app.nostalgex.tv

import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.fillMaxHeight
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
import app.nostalgex.presentation.GuideRow
import app.nostalgex.presentation.LoadStatus
import app.nostalgex.presentation.OsdInfo
import app.nostalgex.presentation.OsdModel
import app.nostalgex.presentation.OsdVisibility
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Live TV. The guide opens first (live preview top-right) and again on Menu/OK/Left; in fullscreen
 * D-pad Up/Down change channel, OK/Menu open the guide, Play/Pause toggles subtitles, and Back exits.
 * The player view is one view that resizes between the two layouts, so the stream never restarts.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun PlaybackScreen(container: AppContainer, session: JellyfinSession, ready: LoadStatus.Ready, onExit: () -> Unit) {
    val context = LocalContext.current
    var state by remember { mutableStateOf<PlaybackState>(PlaybackState.Idle) }
    var currentChannelId by remember { mutableStateOf(-1) }
    var nowSec by remember { mutableLongStateOf(container.clock.instant().epochSecond) }
    val osd = remember { OsdVisibility(hideAfterSec = 5) }
    val engine = remember { Media3PlayerEngine(context) }
    val backend = remember { container.newBackend(session) }
    val subtitlePref = remember { container.subtitlePreference }
    var subtitlesEnabled by remember { mutableStateOf(subtitlePref.enabled) }
    val controller = remember {
        container.newPlaybackController(session, engine, backend).also {
            it.subtitlesEnabled = subtitlePref.enabled
            it.onState = { s ->
                state = s
                when (s) {
                    is PlaybackState.Playing -> currentChannelId = s.channel.id
                    is PlaybackState.Failed -> s.channel?.let { c -> currentChannelId = c.id }
                    else -> {}
                }
                if (s is PlaybackState.Playing) osd.show(container.clock.instant().epochSecond)
            }
        }
    }
    val focus = remember { FocusRequester() }
    val guideModel = remember { container.newGuideModel(session) }
    var guideWanted by remember { mutableStateOf(true) } // the guide is the first thing you see
    var guideRows by remember { mutableStateOf<List<GuideRow>?>(null) }
    val guideVisible = guideWanted && guideRows != null
    val overviews = remember { HashMap<String, String?>() }

    DisposableEffect(Unit) {
        // Start on the first channel that is on air; if none is, the last attempt shows "Nothing scheduled".
        ready.lineups.any { controller.tune(it) }
        onDispose { controller.stop(); engine.release() }
    }
    // Tick once a second so the banner's countdown, now-line and progress stay current.
    LaunchedEffect(Unit) {
        while (true) { nowSec = container.clock.instant().epochSecond; delay(1000) }
    }
    LaunchedEffect(Unit) { focus.requestFocus() }
    // Build now/next rows off the UI thread, and refresh them while the guide is open.
    LaunchedEffect(guideWanted) {
        while (guideWanted) {
            guideRows = withContext(Dispatchers.Default) { guideModel.rows(ready.lineups) }
            delay(30_000)
        }
    }
    LaunchedEffect(guideVisible) { if (!guideVisible) runCatching { focus.requestFocus() } }
    BackHandler(enabled = guideVisible) { guideWanted = false }
    BackHandler(enabled = !guideVisible, onBack = onExit)

    fun toggleSubtitles() {
        subtitlesEnabled = !subtitlesEnabled
        subtitlePref.enabled = subtitlesEnabled
        controller.subtitlesEnabled = subtitlesEnabled
        osd.show(container.clock.instant().epochSecond)
    }

    val info = OsdModel.describe(state, nowSec)

    Box(
        Modifier.fillMaxSize().background(Color.Black)
            .focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (guideVisible || e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionUp, Key.ChannelUp -> { controller.channelUp(ready.lineups); true }
                    Key.DirectionDown, Key.ChannelDown -> { controller.channelDown(ready.lineups); true }
                    Key.Menu, Key.DirectionLeft, Key.DirectionCenter, Key.Enter, Key.NumPadEnter -> { guideWanted = true; true }
                    Key.MediaPlayPause, Key.MediaPlay, Key.MediaPause -> { toggleSubtitles(); true }
                    else -> false
                }
            },
    ) {
        // One player view for both layouts: full screen, or the top-right preview beside the guide.
        AndroidView(
            modifier = if (guideVisible) Modifier.align(Alignment.TopEnd).fillMaxWidth(0.38f).fillMaxHeight(0.5f) else Modifier.fillMaxSize(),
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    useController = false
                    isFocusable = false
                    player = engine.player
                }
            },
            update = { it.resizeMode = if (guideVisible) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT },
        )
        (state as? PlaybackState.Failed)?.let {
            Box(
                if (guideVisible) Modifier.align(Alignment.TopEnd).fillMaxWidth(0.38f).fillMaxHeight(0.5f) else Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) { Text(it.reason, color = Color(0xFFFF6B6B), fontSize = 18.sp) }
        }
        guideRows?.takeIf { guideWanted }?.let { rows ->
            GuideScreen(
                rows = rows, lineups = ready.lineups, model = guideModel, currentChannelId = currentChannelId,
                nowSec = { nowSec }, subtitlesEnabled = subtitlesEnabled,
                loadOverview = { item ->
                    // Cached per item; a failed fetch is not cached so it can be retried.
                    if (overviews.containsKey(item.id)) overviews[item.id]
                    else backend.overview(item).also { overviews[item.id] = it }
                },
                onTune = { row -> ready.lineups.firstOrNull { it.channel.id == row.channel.id }?.let { controller.tune(it) } },
                onFullscreen = { guideWanted = false },
                onToggleSubtitles = ::toggleSubtitles,
            )
        }
        if (!guideVisible && info != null && osd.isVisible(nowSec)) Banner(info, subtitlesEnabled, Modifier.align(Alignment.BottomStart))
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun Banner(info: OsdInfo, subtitlesEnabled: Boolean, modifier: Modifier = Modifier) {
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
                append("   |   CC ").append(if (subtitlesEnabled) "on" else "off").append(" (Play/Pause)")
            },
            color = Color.Gray, fontSize = 16.sp,
        )
    }
}
