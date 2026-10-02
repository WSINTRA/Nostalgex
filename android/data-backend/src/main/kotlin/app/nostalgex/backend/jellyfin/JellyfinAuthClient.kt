package app.nostalgex.backend.jellyfin

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/** Why a sign-in failed. Each case maps to a different fix, per docs/FAQ.md. */
sealed class SignInError(message: String) : Exception(message) {
    class BadCredentials : SignInError("Wrong username or password")
    class NotJellyfin : SignInError("That address returned a web page, not a Jellyfin server")
    class ServerError(val code: Int) : SignInError("Server answered HTTP $code")
    class Timeout : SignInError("Timed out reaching the server")
    class ConnectionRefused : SignInError("Connection refused: check the port")
    class UnknownHost : SignInError("Unknown host: check the address")
    class Certificate : SignInError("Certificate problem on an https address")
    class Network(cause: Throwable) : SignInError("Network error: ${cause.message}")

    /** True when trying another address could still help. */
    val isUnreachable get() = this is Timeout || this is ConnectionRefused || this is UnknownHost || this is Network || this is NotJellyfin
}

data class JellyfinSession(val baseUrl: String, val accessToken: String, val userId: String, val serverId: String, val serverName: String)

class JellyfinAuthClient(
    private val client: OkHttpClient,
    private val deviceId: String,
    private val deviceName: String = "Fire TV",
) {
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable private data class UserDto(val Id: String? = null, val ServerName: String? = null)
    @Serializable private data class AuthDto(val AccessToken: String? = null, val User: UserDto? = null, val ServerId: String? = null)

    suspend fun signIn(baseUrl: String, username: String, password: String): JellyfinSession = withContext(Dispatchers.IO) {
        val body = buildString {
            append("{\"Username\":").append(Json.encodeToString(kotlinx.serialization.serializer<String>(), username))
            append(",\"Pw\":").append(Json.encodeToString(kotlinx.serialization.serializer<String>(), password)).append('}')
        }
        val req = Request.Builder()
            .url("$baseUrl/Users/AuthenticateByName")
            .header("Accept", "application/json")
            .header("Authorization", authorizationHeader(deviceId, deviceName, token = ""))
            .post(body.toRequestBody("application/json".toMediaType()))
            .build()
        val (code, text) = try {
            client.newCall(req).execute().use { it.code to it.body?.string().orEmpty() }
        } catch (e: IOException) {
            throw classify(e)
        }
        when {
            code == 401 || code == 403 -> throw SignInError.BadCredentials()
            code !in 200..299 -> throw SignInError.ServerError(code)
            text.trimStart().startsWith("<") -> throw SignInError.NotJellyfin()
        }
        val dto = try { json.decodeFromString(AuthDto.serializer(), text) } catch (e: Exception) { throw SignInError.NotJellyfin() }
        val token = dto.AccessToken
        val uid = dto.User?.Id
        if (token == null || uid == null) throw SignInError.BadCredentials()
        JellyfinSession(baseUrl, token, uid, dto.ServerId.orEmpty(), dto.User.ServerName ?: "Jellyfin Server")
    }

    /** Tries each candidate; stops at the first answer, including a definitive failure like bad credentials. */
    suspend fun signInFirstReachable(candidates: List<String>, username: String, password: String): JellyfinSession {
        var last: SignInError = SignInError.UnknownHost()
        for (url in candidates) {
            try { return signIn(url, username, password) } catch (e: SignInError) {
                if (!e.isUnreachable) throw e
                last = e
            }
        }
        throw last
    }

    private fun classify(e: IOException): SignInError = when (e) {
        is SocketTimeoutException -> SignInError.Timeout()
        is UnknownHostException -> SignInError.UnknownHost()
        is ConnectException -> SignInError.ConnectionRefused()
        is SSLException -> SignInError.Certificate()
        else -> if (e.message?.contains("timeout", ignoreCase = true) == true) SignInError.Timeout() else SignInError.Network(e)
    }

    companion object {
        /** `MediaBrowser` authorization scheme; Token omitted before sign-in. */
        fun authorizationHeader(deviceId: String, deviceName: String, token: String): String {
            val fields = mutableListOf("Client=\"Nostalgex\"", "Device=\"$deviceName\"", "DeviceId=\"$deviceId\"", "Version=\"1.0\"")
            if (token.isNotEmpty()) fields += "Token=\"$token\""
            return "MediaBrowser " + fields.joinToString(", ")
        }
    }
}
