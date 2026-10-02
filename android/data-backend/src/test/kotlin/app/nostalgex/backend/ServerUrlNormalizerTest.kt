package app.nostalgex.backend

import kotlin.test.Test
import kotlin.test.assertEquals

class ServerUrlNormalizerTest {
    private fun first(s: String) = ServerUrlNormalizer.normalize(s)

    @Test fun `bare ip gets http and 8096`() = assertEquals("http://192.168.1.10:8096", first("192.168.1.10"))
    @Test fun `typed port is kept`() = assertEquals("http://host:9000", first("http://host:9000"))
    @Test fun `https gets no port`() = assertEquals("https://jf.example.com", first("https://jf.example.com"))
    @Test fun `web ui path and trailing slash are dropped`() =
        assertEquals("http://h:8096", first("http://h:8096/web/#/home"))
    @Test fun `proxy base path is kept`() = assertEquals("https://h/jellyfin", first("https://h/jellyfin/"))
    @Test fun `whitespace and uppercase scheme`() = assertEquals("http://h:8096", first("  HTTP://H  "))
    @Test fun `portless http offers 8096 then portless`() =
        assertEquals(listOf("http://h:8096", "http://h"), ServerUrlNormalizer.candidates("h"))
    @Test fun `empty input gives nothing`() = assertEquals(emptyList(), ServerUrlNormalizer.candidates("   "))
    @Test fun `ipv6 literal keeps brackets`() = assertEquals("http://[::1]:8096", first("::1"))
}
