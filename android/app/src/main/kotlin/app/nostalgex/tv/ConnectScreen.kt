package app.nostalgex.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.Text
import app.nostalgex.presentation.ConnectModel
import app.nostalgex.presentation.ConnectStatus
import app.nostalgex.backend.jellyfin.JellyfinSession
import kotlinx.coroutines.launch

/**
 * Connect screen. Focus order (D-pad down): server, username, password, Connect.
 * Enter on a field opens the on-screen keyboard; Next/Done moves on.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun ConnectScreen(model: ConnectModel, onConnected: (JellyfinSession) -> Unit) {
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val first = remember { FocusRequester() }

    LaunchedEffect(Unit) { first.requestFocus() }
    LaunchedEffect(state.status) { (state.status as? ConnectStatus.Connected)?.let { onConnected(it.session) } }

    Column(
        Modifier.fillMaxSize().background(Color.Black).padding(horizontal = 160.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
    ) {
        Text("NOSTALGEX", color = Color(0xFFFFE500), fontSize = 40.sp)
        Text("Connect to your Jellyfin server", color = Color.White, fontSize = 22.sp)

        Field("Server address (e.g. 192.168.1.20)", state.server, model::setServer, ImeAction.Next, KeyboardType.Uri, modifier = Modifier.focusRequester(first))
        Field("Username", state.username, model::setUsername, ImeAction.Next, KeyboardType.Text)
        Field("Password", state.password, model::setPassword, ImeAction.Done, KeyboardType.Password, PasswordVisualTransformation()) {
            if (state.canSubmit) scope.launch { model.submit() }
        }

        Button(onClick = { scope.launch { model.submit() } }, enabled = state.canSubmit, modifier = Modifier.width(220.dp)) {
            Text(if (state.status == ConnectStatus.Connecting) "Connecting..." else "Connect")
        }
        (state.status as? ConnectStatus.Failed)?.let { Text(it.message, color = Color(0xFFFF6B6B), fontSize = 18.sp) }
    }
}

@Composable
private fun Field(
    label: String, value: String, onChange: (String) -> Unit, ime: ImeAction, type: KeyboardType,
    transform: VisualTransformation = VisualTransformation.None, modifier: Modifier = Modifier, onDone: () -> Unit = {},
) {
    var focused by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Text(label, color = Color.Gray, fontSize = 14.sp)
        BasicTextField(
            value = value, onValueChange = onChange, singleLine = true, visualTransformation = transform,
            textStyle = TextStyle(color = Color.White, fontSize = 22.sp),
            cursorBrush = SolidColor(Color.White),
            keyboardOptions = KeyboardOptions(keyboardType = type, imeAction = ime),
            keyboardActions = KeyboardActions(onDone = { onDone() }),
            modifier = modifier.fillMaxWidth()
                .onFocusChanged { focused = it.isFocused }
                .border(2.dp, if (focused) Color(0xFFFFE500) else Color.DarkGray)
                .padding(12.dp),
        )
    }
}
