package app.nostalgex.store

import app.nostalgex.schedule.StoredBlock
import app.nostalgex.schedule.StoredDay
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class FileManifestStoreTest {
    private val dir = Files.createTempDirectory("man").toFile().also { it.deleteOnExit() }
    private val store = FileManifestStore(dir)
    private val day = StoredDay("2026-06-15", "fp", listOf(StoredBlock("a", 0, 100), StoredBlock("b", 100, 200)))

    @Test fun `missing day is null`() = assertNull(store.load(1, "2026-06-15"))

    @Test fun `round trips`() {
        store.save(1, day)
        assertEquals(day, store.load(1, "2026-06-15"))
    }

    @Test fun `keyed by channel and day`() {
        store.save(1, day); store.save(2, day.copy(poolFingerprint = "other"))
        assertEquals("fp", store.load(1, "2026-06-15")!!.poolFingerprint)
        assertEquals("other", store.load(2, "2026-06-15")!!.poolFingerprint)
        assertNull(store.load(1, "2026-06-16"))
    }

    @Test fun `corrupt file is null`() {
        store.save(1, day)
        dir.listFiles()!!.single().writeText("garbage")
        assertNull(store.load(1, "2026-06-15"))
    }

    @Test fun `prune drops days older than the cutoff`() {
        listOf("2026-06-10", "2026-06-14", "2026-06-15").forEach { store.save(1, day.copy(dayKey = it)) }
        store.pruneBefore("2026-06-14")
        assertNull(store.load(1, "2026-06-10"))
        assertEquals("2026-06-14", store.load(1, "2026-06-14")!!.dayKey)
        assertEquals("2026-06-15", store.load(1, "2026-06-15")!!.dayKey)
    }
}
