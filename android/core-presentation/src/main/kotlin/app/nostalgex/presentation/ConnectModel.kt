package app.nostalgex.presentation

import app.nostalgex.backend.ServerUrlNormalizer
import app.nostalgex.backend.jellyfin.JellyfinSession
import app.nostalgex.backend.jellyfin.SignInError
import app.nostalgex.store.SessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Seam over the sign-in call so the model is tested without a network. */
fun interface SignInService {
    suspend fun signIn(candidates: List<String>, username: String, password: String): JellyfinSession
}

sealed interface ConnectStatus {
    data object Idle : ConnectStatus
    data object Connecting : ConnectStatus
    data class Failed(val message: String) : ConnectStatus
    data class Connected(val session: JellyfinSession) : ConnectStatus
}

data class ConnectState(
    val server: String = "",
    val username: String = "",
    val password: String = "",
    val status: ConnectStatus = ConnectStatus.Idle,
) {
    val canSubmit get() = server.isNotBlank() && username.isNotBlank() && status != ConnectStatus.Connecting
}

/** Logic of the connect screen. The Compose UI only renders [state] and forwards input. */
class ConnectModel(private val service: SignInService, private val sessions: SessionStore) {
    private val _state = MutableStateFlow(ConnectState())
    val state: StateFlow<ConnectState> = _state.asStateFlow()

    fun setServer(v: String) = edit { copy(server = v) }
    fun setUsername(v: String) = edit { copy(username = v) }
    fun setPassword(v: String) = edit { copy(password = v) }

    suspend fun submit() {
        val s = _state.value
        if (!s.canSubmit) return
        val candidates = ServerUrlNormalizer.candidates(s.server)
        if (candidates.isEmpty()) { setStatus(ConnectStatus.Failed("Enter your server address, for example 192.168.1.20")); return }
        setStatus(ConnectStatus.Connecting)
        try {
            val session = service.signIn(candidates, s.username.trim(), s.password)
            sessions.save(session)
            setStatus(ConnectStatus.Connected(session))
        } catch (e: CancellationException) {
            throw e
        } catch (e: SignInError) {
            setStatus(ConnectStatus.Failed(describe(e)))
        } catch (e: Exception) {
            setStatus(ConnectStatus.Failed("Something went wrong: ${e.message ?: e::class.simpleName}"))
        }
    }

    /** One actionable sentence per failure, following docs/FAQ.md. */
    internal fun describe(e: SignInError): String = when (e) {
        is SignInError.BadCredentials -> "Wrong username or password."
        is SignInError.UnknownHost -> "Unknown host. Check the address, including any typos."
        is SignInError.ConnectionRefused -> "Connection refused. Check the port (Jellyfin's default is 8096)."
        is SignInError.Timeout -> "Could not reach the server in time. Is it on and on the same network?"
        is SignInError.Certificate -> "Certificate problem. For https the certificate must be valid; otherwise use http on your local IP."
        is SignInError.NotJellyfin -> "That address answered with a web page, not Jellyfin. Check the address and port."
        is SignInError.ServerError -> "The server answered with an error (HTTP ${e.code})."
        is SignInError.Network -> "Network error: ${e.message}"
    }

    private fun edit(block: ConnectState.() -> ConnectState) =
        _state.update { it.block().let { n -> if (n.status is ConnectStatus.Failed) n.copy(status = ConnectStatus.Idle) else n } }

    private fun setStatus(s: ConnectStatus) = _state.update { it.copy(status = s) }
}
