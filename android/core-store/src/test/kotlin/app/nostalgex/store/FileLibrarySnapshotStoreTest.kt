package app.nostalgex.store

import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaItem
import app.nostalgex.model.MediaType
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class FileLibrarySnapshotStoreTest {
    private val dir = Files.createTempDirectory("snap").toFile().also { it.deleteOnExit() }
    private val store = FileLibrarySnapshotStore(dir)
    private val items = listOf(
        MediaItem("1", "Heat", 120, MediaType.MOVIE, year = 1995, genres = listOf("Action"), studios = listOf("WB"),
            librarySource = LibrarySource.MOVIE, mediaSourceId = "s1", bitrateKbps = 4000, communityRating = 8.2),
        MediaItem("2", "Show", 22, MediaType.EPISODE, seTag = "S01E01", librarySource = LibrarySource.TV),
    )

    @Test fun `missing snapshot is null`() = assertNull(store.load("srv"))

    @Test fun `round trips every item field`() {
        store.save(LibrarySnapshot("srv", 1234L, items))
        val back = assertNotNull(store.load("srv"))
        assertEquals(items, back.items); assertEquals(1234L, back.savedAtEpochSec); assertEquals("srv", back.serverId)
    }

    @Test fun `snapshots are per server`() {
        store.save(LibrarySnapshot("a", 1, items.take(1)))
        store.save(LibrarySnapshot("b", 2, items))
        assertEquals(1, store.load("a")!!.items.size); assertEquals(2, store.load("b")!!.items.size)
    }

    @Test fun `server ids with odd characters are safe`() {
        store.save(LibrarySnapshot("http://h:8096/../x", 1, items))
        assertNotNull(store.load("http://h:8096/../x"))
        assertEquals(1, dir.listFiles()!!.size)
    }

    @Test fun `corrupt file reads as null`() {
        store.save(LibrarySnapshot("srv", 1, items))
        dir.listFiles()!!.single().writeText("{broken")
        assertNull(store.load("srv"))
    }

    @Test fun `save overwrites and leaves no temp files`() {
        store.save(LibrarySnapshot("srv", 1, items)); store.save(LibrarySnapshot("srv", 2, items.take(1)))
        assertEquals(2L, store.load("srv")!!.savedAtEpochSec)
        assertEquals(1, dir.listFiles()!!.size)
    }

    @Test fun `clear removes the snapshot`() {
        store.save(LibrarySnapshot("srv", 1, items)); store.clear("srv")
        assertNull(store.load("srv"))
    }
}
