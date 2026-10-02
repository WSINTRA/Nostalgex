package app.nostalgex.backend

import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** Documents the contract consumers can rely on from any [MediaBackend]. */
class FakeMediaBackendTest {
    private val item = MediaItem("1", "Heat", 120, MediaType.MOVIE)

    @Test fun `connection returns server name`() = runTest {
        assertEquals("Home", FakeMediaBackend(serverName = "Home").testConnection())
    }

    @Test fun `library load reports progress and returns items`() = runTest {
        val seen = mutableListOf<LoadProgress>()
        val out = FakeMediaBackend(listOf(item)).loadLibrary { seen += it }
        assertEquals(listOf(item), out)
        assertEquals(1, seen.single().itemsLoadedSoFar)
    }

    @Test fun `failures propagate`() = runTest {
        val b = FakeMediaBackend(failure = IllegalStateException("down"))
        assertFailsWith<IllegalStateException> { b.testConnection() }
        assertFailsWith<IllegalStateException> { b.loadLibrary() }
    }
}
