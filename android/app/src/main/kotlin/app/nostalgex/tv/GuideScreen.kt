package app.nostalgex.tv

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import app.nostalgex.presentation.GuideModel
import app.nostalgex.presentation.GuideRow

/**
 * Channel guide: one text row per channel with what is on now and next. Text only, no artwork and a
 * lazy list, so it stays smooth on an older stick. Up/Down move, OK tunes, Back closes.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun GuideScreen(rows: List<GuideRow>, currentChannelId: Int, onPick: (GuideRow) -> Unit, onClose: () -> Unit) {
    val start = remember(rows) { GuideModel.indexOfChannel(rows, currentChannelId) }
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, start - 3))
    val focus = remember { FocusRequester() }
    BackHandler(onBack = onClose)
    LaunchedEffect(rows) { if (rows.isNotEmpty()) runCatching { focus.requestFocus() } }

    Column(Modifier.fillMaxSize().background(Color(0xF2000000)).padding(horizontal = 64.dp, vertical = 32.dp)) {
        Text("GUIDE", color = Color(0xFFFFE500), fontSize = 28.sp)
        Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 6.dp)) {
            Text("Channel", color = Color.Gray, fontSize = 14.sp, modifier = Modifier.width(260.dp))
            Text("Now", color = Color.Gray, fontSize = 14.sp, modifier = Modifier.weight(1f))
            Text("Next", color = Color.Gray, fontSize = 14.sp, modifier = Modifier.weight(1f))
        }
        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
            itemsIndexed(rows, key = { _, r -> r.channel.id }) { index, row ->
                GuideRowItem(row, isCurrent = row.channel.id == currentChannelId, onPick = { onPick(row) },
                    modifier = if (index == start) Modifier.focusRequester(focus) else Modifier)
            }
        }
    }
}

@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun GuideRowItem(row: GuideRow, isCurrent: Boolean, onPick: () -> Unit, modifier: Modifier) {
    var focused by remember { mutableStateOf(false) }
    Box(
        modifier.fillMaxWidth().padding(vertical = 2.dp)
            .onFocusChanged { focused = it.isFocused }
            .background(if (focused) Color(0xFF2A2A2A) else Color.Transparent)
            .border(2.dp, if (focused) Color(0xFFFFE500) else Color.Transparent)
            .clickable(onClick = onPick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(0.dp)) {
            Text(
                "${row.channel.number}  ${row.channel.name}" + if (isCurrent) "  *" else "",
                color = Color(0xFFFFE500), fontSize = 18.sp, maxLines = 1, modifier = Modifier.width(260.dp),
            )
            Column(Modifier.weight(1f)) {
                Text("${row.nowStartLabel}  ${row.nowTitle}", color = Color.White, fontSize = 18.sp, maxLines = 1)
                Box(Modifier.padding(top = 4.dp).fillMaxWidth(0.8f).height(3.dp).background(Color.DarkGray)) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(row.progress).background(Color(0xFFFFE500)))
                }
            }
            Text(
                row.nextTitle?.let { "${row.nextStartLabel}  $it" } ?: "",
                color = Color.LightGray, fontSize = 16.sp, maxLines = 1, modifier = Modifier.weight(1f),
            )
        }
    }
}
