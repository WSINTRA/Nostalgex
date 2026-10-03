package app.nostalgex.tv

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import app.nostalgex.filter.ChannelLineup
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import app.nostalgex.presentation.GuideFormat
import app.nostalgex.presentation.GuideModel
import app.nostalgex.presentation.GuideRow
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

private val Mono = FontFamily(Font(R.font.dmmono_medium))
private val Navy = Color(0xFF0D0D1F)
private val HeaderBg = Color(0xFF0A0A14)
private val NowCyan = Color(0xFF00D4FF)

private val ChannelCol = 150.dp
private val AccentWidth = 6.dp
private val RowHeight = 54.dp
private val HeaderHeight = 40.dp

private const val WINDOW_SEC = 7200L // two hours visible
private const val SLOT_SEC = 1800L
private const val MAX_SLOT_OFFSET = 44 // 24 hours ahead

/**
 * Guide in the tvOS layout: info panel top-left, live preview top-right (the player view sits behind
 * the transparent area), and a two-hour timeline grid below. Up/Down move and wrap, Left/Right scroll
 * time, OK tunes (or goes fullscreen on the live channel), Play/Pause toggles subtitles.
 * Back is handled by the caller.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun GuideScreen(
    rows: List<GuideRow>,
    lineups: List<ChannelLineup>,
    model: GuideModel,
    currentChannelId: Int,
    nowSec: () -> Long,
    subtitlesEnabled: Boolean,
    loadOverview: suspend (MediaItem) -> String?,
    onTune: (GuideRow) -> Unit,
    onFullscreen: () -> Unit,
    onToggleSubtitles: () -> Unit,
) {
    val lineupById = remember(lineups) { lineups.associateBy { it.channel.id } }
    var selected by remember { mutableIntStateOf(GuideModel.indexOfChannel(rows, currentChannelId)) }
    var slotOffset by remember { mutableIntStateOf(0) }
    val baseStart = remember { GuideModel.snapToHalfHour(nowSec()) }
    val windowStart = baseStart + slotOffset * SLOT_SEC
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, selected - 2))
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    val last = rows.size - 1
    if (selected > last) selected = maxOf(0, last)

    // Keep the selected row on screen; jump so it sits mid-list when it leaves the view (e.g. on wrap).
    LaunchedEffect(selected) {
        val visible = listState.layoutInfo.visibleItemsInfo
        if (visible.isEmpty()) return@LaunchedEffect
        if (selected <= visible.first().index || selected >= visible.last().index) {
            listState.animateScrollToItem(maxOf(0, selected - 2))
        }
    }

    Column(
        Modifier.fillMaxSize()
            .focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown || rows.isEmpty()) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionUp, Key.ChannelUp -> { selected = Math.floorMod(selected - 1, rows.size); true }
                    Key.DirectionDown, Key.ChannelDown -> { selected = Math.floorMod(selected + 1, rows.size); true }
                    Key.DirectionLeft -> { slotOffset = maxOf(0, slotOffset - 1); true }
                    Key.DirectionRight -> { slotOffset = minOf(MAX_SLOT_OFFSET, slotOffset + 1); true }
                    Key.MediaPlayPause, Key.MediaPlay, Key.MediaPause -> { onToggleSubtitles(); true }
                    Key.DirectionCenter, Key.Enter, Key.NumPadEnter -> {
                        val row = rows[selected]
                        if (row.channel.id == currentChannelId) onFullscreen() else if (row.onAir) onTune(row)
                        true
                    }
                    else -> false
                }
            },
    ) {
        Row(Modifier.fillMaxWidth().weight(1f)) {
            InfoPanel(
                row = rows.getOrNull(selected), nowSec = nowSec, subtitlesEnabled = subtitlesEnabled,
                loadOverview = loadOverview, modifier = Modifier.weight(0.62f).fillMaxHeight(),
            )
            Spacer(Modifier.weight(0.38f).fillMaxHeight()) // the live preview shows through here
        }
        Grid(
            rows = rows, lineupById = lineupById, model = model, selected = selected, currentChannelId = currentChannelId,
            windowStart = windowStart, nowSec = nowSec, listState = listState, modifier = Modifier.weight(1f).fillMaxWidth(),
        )
    }
}

// --- Info panel ---------------------------------------------------------------------------------

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun InfoPanel(
    row: GuideRow?, nowSec: () -> Long, subtitlesEnabled: Boolean,
    loadOverview: suspend (MediaItem) -> String?, modifier: Modifier,
) {
    Column(modifier.background(Navy).padding(horizontal = 28.dp, vertical = 16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Image(
                painterResource(R.drawable.nostalgex_logo), contentDescription = "Nostalgex",
                modifier = Modifier.height(36.dp), contentScale = ContentScale.Fit,
            )
            Spacer(Modifier.weight(1f))
            Chip(if (subtitlesEnabled) "CC ON" else "CC OFF", highlight = subtitlesEnabled)
            Text("  PLAY/PAUSE", color = Color.White.copy(alpha = 0.35f), fontFamily = Mono, fontSize = 11.sp)
        }
        Spacer(Modifier.weight(1f))
        if (row == null) return@Column

        val accent = Color(row.colorArgb)
        val item = row.nowItem
        Text(
            "CH ${row.channel.number} - ${row.channel.name.uppercase()}",
            color = accent, fontFamily = Mono, fontSize = 15.sp, letterSpacing = 2.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
        Text(
            if (row.onAir) row.nowTitle else "Off air",
            color = Color.White, fontFamily = Mono, fontSize = 26.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 4.dp),
        )
        val episode = item?.takeIf { it.type == MediaType.EPISODE }
            ?.let { listOfNotNull(it.seTag, it.episodeTitle).joinToString("  ") }?.takeIf { it.isNotBlank() }
        if (episode != null) Text(episode, color = Color.White.copy(alpha = 0.7f), fontFamily = Mono, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Box(Modifier.padding(vertical = 8.dp).fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.1f)))

        // The description is fetched on demand for the focused programme, after a short pause so
        // scrolling through channels does not fire a request per row.
        val overview by produceState<String?>(null, item?.id) {
            value = null
            if (item != null) { delay(400); value = runCatching { loadOverview(item) }.getOrNull() }
        }
        Box(Modifier.height(54.dp)) {
            Text(overview.orEmpty(), color = Color.White.copy(alpha = 0.55f), fontFamily = Mono, fontSize = 12.sp, lineHeight = 18.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }

        if (item != null) {
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item.year?.let { Chip(it.toString()) }
                item.contentRating?.takeIf { it.isNotBlank() }?.let { Chip(it) }
                if (item.communityRating > 0) Text("\u2605 ${"%.1f".format(item.communityRating)}", color = Color(0xFFFFC857), fontFamily = Mono, fontSize = 12.sp)
                val total = maxOf(1L, row.nowEndEpochSec - row.nowStartEpochSec)
                ProgressBar(Modifier.weight(1f), accent) { ((nowSec() - row.nowStartEpochSec).toFloat() / total).coerceIn(0f, 1f) }
                ElapsedLabel(nowSec, row.nowStartEpochSec, total)
            }
        }
        Text(
            "UP NEXT  ${row.nextTitle.orEmpty()}",
            color = Color.White.copy(alpha = 0.45f), fontFamily = Mono, fontSize = 12.sp, letterSpacing = 1.sp,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun ElapsedLabel(nowSec: () -> Long, startSec: Long, totalSec: Long) {
    // Reads the ticking clock here so only this label recomposes each second.
    Text(GuideFormat.elapsedOfTotal(nowSec() - startSec, totalSec), color = Color.White.copy(alpha = 0.4f), fontFamily = Mono, fontSize = 11.sp, maxLines = 1)
}

@Composable
private fun ProgressBar(modifier: Modifier, color: Color, fraction: () -> Float) {
    Box(modifier.height(3.dp).background(Color.White.copy(alpha = 0.15f))) {
        Box(Modifier.fillMaxHeight().fillMaxWidth().graphicsLayer {
            // Scale from the left edge in the draw phase, so ticking does not recompose.
            transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0f, 0.5f)
            scaleX = fraction()
        }.background(color))
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun Chip(text: String, highlight: Boolean = false) {
    Box(
        Modifier.border(1.dp, if (highlight) NowCyan else Color.White.copy(alpha = 0.25f), RoundedCornerShape(4.dp))
            .padding(horizontal = 8.dp, vertical = 3.dp),
    ) { Text(text, color = if (highlight) NowCyan else Color.White.copy(alpha = 0.7f), fontFamily = Mono, fontSize = 12.sp, maxLines = 1) }
}

// --- Grid ---------------------------------------------------------------------------------------

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun Grid(
    rows: List<GuideRow>, lineupById: Map<Int, ChannelLineup>, model: GuideModel, selected: Int, currentChannelId: Int,
    windowStart: Long, nowSec: () -> Long, listState: androidx.compose.foundation.lazy.LazyListState, modifier: Modifier,
) {
    BoxWithConstraints(modifier.background(Navy)) {
        val programsWidth = maxWidth - ChannelCol
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().height(HeaderHeight).background(HeaderBg), verticalAlignment = Alignment.CenterVertically) {
                Text("CHANNEL", color = Color.White.copy(alpha = 0.7f), fontFamily = Mono, fontSize = 11.sp, modifier = Modifier.width(ChannelCol).padding(start = 12.dp))
                val labels = remember(windowStart) { (0 until 4).map { model.timeLabel(windowStart + it * SLOT_SEC) } }
                labels.forEach {
                    Box(Modifier.width(programsWidth / 4).fillMaxHeight()) {
                        Box(Modifier.width(1.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.2f)))
                        Text(it, color = Color.White.copy(alpha = 0.95f), fontFamily = Mono, fontSize = 14.sp, modifier = Modifier.align(Alignment.CenterStart).padding(start = 10.dp))
                    }
                }
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.25f)))
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                itemsIndexed(rows, key = { _, r -> r.channel.id }) { index, row ->
                    val cells = remember(row, windowStart) { lineupById[row.channel.id]?.let { model.cells(it, windowStart, WINDOW_SEC) } }
                    GuideRowItem(
                        row = row, cells = cells?.cells.orEmpty(), isSelected = index == selected,
                        isLive = row.channel.id == currentChannelId, isEven = index % 2 == 0, programsWidth = programsWidth,
                    )
                }
            }
        }
        NowLine(nowSec, windowStart, programsWidth)
    }
}

@Composable
private fun NowLine(nowSec: () -> Long, windowStart: Long, programsWidth: androidx.compose.ui.unit.Dp) {
    val density = LocalDensity.current
    val channelPx = with(density) { ChannelCol.toPx() }
    val programsPx = with(density) { programsWidth.toPx() }
    Box(
        Modifier.fillMaxHeight().width(2.dp)
            .offset { IntOffset((channelPx + programsPx * ((nowSec() - windowStart).toFloat() / WINDOW_SEC)).roundToInt(), 0) }
            .graphicsLayer { alpha = if ((nowSec() - windowStart) in 0..WINDOW_SEC) 1f else 0f }
            .background(NowCyan),
    )
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun GuideRowItem(
    row: GuideRow, cells: List<app.nostalgex.presentation.GuideCell>, isSelected: Boolean, isLive: Boolean,
    isEven: Boolean, programsWidth: androidx.compose.ui.unit.Dp,
) {
    val accent = Color(row.colorArgb)
    val shape = RoundedCornerShape(4.dp)
    Column {
        Row(
            Modifier.fillMaxWidth().height(RowHeight)
                .background(if (isSelected) accent.copy(alpha = 0.32f) else if (isEven) Color.White.copy(alpha = 0.03f) else Color.Transparent)
                .then(if (isSelected) Modifier.border(2.dp, accent, shape) else Modifier),
        ) {
            Box(Modifier.width(AccentWidth).fillMaxHeight().background(if (isLive || isSelected) accent else accent.copy(alpha = 0.4f)))
            Row(Modifier.width(ChannelCol - AccentWidth - 1.dp).fillMaxHeight().padding(start = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (isLive) { Bolt(accent); Spacer(Modifier.width(4.dp)) }
                Text(
                    row.channel.number.toString(), color = if (isSelected) Color.White else accent, fontFamily = Mono, fontSize = 14.sp,
                    modifier = Modifier.width(26.dp), maxLines = 1,
                )
                Text(
                    row.channel.name.uppercase(), color = if (isSelected) Color.White else accent.copy(alpha = 0.95f), fontFamily = Mono,
                    fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 4.dp),
                )
            }
            Box(Modifier.width(1.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.15f)))
            Row(Modifier.width(programsWidth).fillMaxHeight().clipToBounds()) {
                if (!row.onAir) {
                    Text("Off air", color = Color.White.copy(alpha = 0.35f), fontFamily = Mono, fontSize = 14.sp, modifier = Modifier.align(Alignment.CenterVertically).padding(start = 12.dp))
                }
                cells.forEach { c ->
                    val w = maxOf(programsWidth * c.fraction, 1.dp)
                    val title = c.title
                    if (title == null) {
                        Spacer(Modifier.width(w))
                    } else {
                        Box(
                            Modifier.width(w).fillMaxHeight().clipToBounds().background(
                                if (c.isNow) accent.copy(alpha = if (isSelected) 0.55f else 0.25f) else if (c.isPast) Color.White.copy(alpha = 0.02f) else Color.Transparent,
                            ),
                        ) {
                            Box(Modifier.width(1.dp).fillMaxHeight().background(Color.White.copy(alpha = 0.12f)))
                            Text(
                                title, fontFamily = Mono, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                color = Color.White.copy(alpha = if (c.isNow || isSelected) 1f else if (c.isPast) 0.5f else 0.85f),
                                modifier = Modifier.align(Alignment.CenterStart).padding(start = 10.dp, end = 4.dp),
                            )
                        }
                    }
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Color.White.copy(alpha = 0.08f)))
    }
}

/** Lightning bolt on the channel colour, marking the channel that is tuned in. */
@Composable
private fun Bolt(color: Color) {
    Box(Modifier.size(width = 16.dp, height = 20.dp).background(color, RoundedCornerShape(2.dp)), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(width = 8.dp, height = 13.dp)) {
            val w = size.width; val h = size.height
            val p = Path().apply {
                moveTo(w * 0.6f, 0f); lineTo(0f, h * 0.55f); lineTo(w * 0.45f, h * 0.55f)
                lineTo(w * 0.3f, h); lineTo(w, h * 0.4f); lineTo(w * 0.55f, h * 0.4f); close()
            }
            drawPath(p, Color.Black.copy(alpha = 0.9f))
        }
    }
}
