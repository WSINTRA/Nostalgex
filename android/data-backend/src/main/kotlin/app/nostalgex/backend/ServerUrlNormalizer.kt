package app.nostalgex.backend

/** Turns whatever was typed in the server field into base URLs to try. Port of tvOS ServerURLNormalizer. */
object ServerUrlNormalizer {
    const val DEFAULT_HTTP_PORT = 8096

    private data class Parts(val scheme: String?, val userInfo: String?, val host: String, val port: Int?, val rest: String)

    fun normalize(raw: String): String = candidates(raw).firstOrNull().orEmpty()

    fun candidates(raw: String): List<String> {
        val p = split(raw)
        if (p.host.isEmpty()) return emptyList()
        val scheme = p.scheme ?: "http"
        val path = basePath(p.rest)
        fun build(port: Int?) = buildString {
            append(scheme).append("://")
            if (!p.userInfo.isNullOrEmpty()) append(p.userInfo).append('@')
            append(p.host)
            if (port != null) append(':').append(port)
            append(path)
        }
        return if (p.port == null && scheme == "http" && path.isEmpty()) listOf(build(DEFAULT_HTTP_PORT), build(null))
        else listOf(build(p.port))
    }

    private fun split(raw: String): Parts {
        var s = raw.filterNot { it.isWhitespace() }
        var scheme: String? = null
        val sep = s.indexOf("://")
        if (sep > 0) {
            val cand = s.substring(0, sep)
            if (cand.all { it.isLetterOrDigit() || it in "+-." }) { scheme = cand.lowercase(); s = s.substring(sep + 3) }
        }
        val end = s.indexOfFirst { it in "/?#" }.let { if (it < 0) s.length else it }
        var authority = s.substring(0, end)
        val rest = s.substring(end)
        var userInfo: String? = null
        authority.lastIndexOf('@').takeIf { it >= 0 }?.let { userInfo = authority.substring(0, it); authority = authority.substring(it + 1) }

        var host = authority
        var port: Int? = null
        if (authority.startsWith("[") && authority.contains(']')) {
            val close = authority.indexOf(']')
            host = authority.substring(0, close + 1)
            authority.substring(close + 1).takeIf { it.startsWith(":") }?.drop(1)?.toIntOrNull()?.let { port = it }
        } else if (authority.count { it == ':' } == 1) {
            val c = authority.indexOf(':')
            host = authority.substring(0, c)
            port = authority.substring(c + 1).toIntOrNull()
        } else if (authority.contains(':')) host = "[$authority]"
        return Parts(scheme, userInfo, host.lowercase(), port, rest)
    }

    /** Drops query, fragment, `/web` UI path and trailing slashes; keeps a proxy base path. */
    private fun basePath(rest: String): String {
        val path = rest.substringBefore('?').substringBefore('#')
        val parts = path.split('/').filter { it.isNotEmpty() }
        val web = parts.indexOfFirst { it.equals("web", ignoreCase = true) }
        val kept = if (web >= 0) parts.take(web) else parts
        return if (kept.isEmpty()) "" else "/" + kept.joinToString("/")
    }
}
