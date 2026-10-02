package app.nostalgex.store

import app.nostalgex.schedule.ManifestStore
import app.nostalgex.schedule.StoredBlock
import app.nostalgex.schedule.StoredDay
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** One JSON file per channel-day, so yesterday's aired list survives restarts (tvOS: DailyManifestStore). */
class FileManifestStore(private val dir: File) : ManifestStore {
    @Serializable private data class BlockDto(val id: String, val start: Long, val end: Long)
    @Serializable private data class DayDto(val dayKey: String, val poolFingerprint: String, val blocks: List<BlockDto>)

    private val json = Json { ignoreUnknownKeys = true }

    override fun load(channelId: Int, dayKey: String): StoredDay? {
        val f = file(channelId, dayKey)
        if (!f.exists()) return null
        return try {
            json.decodeFromString(DayDto.serializer(), f.readText()).let { d ->
                StoredDay(d.dayKey, d.poolFingerprint, d.blocks.map { StoredBlock(it.id, it.start, it.end) })
            }
        } catch (e: Exception) { null }
    }

    override fun save(channelId: Int, day: StoredDay) {
        val dto = DayDto(day.dayKey, day.poolFingerprint, day.blocks.map { BlockDto(it.id, it.startEpochSec, it.endEpochSec) })
        atomicWrite(file(channelId, day.dayKey), json.encodeToString(DayDto.serializer(), dto))
    }

    /** Deletes manifests for days strictly before [dayKey] (ISO dates compare correctly as strings). */
    fun pruneBefore(dayKey: String) {
        dir.listFiles()?.forEach { f ->
            val m = NAME.matchEntire(f.name) ?: return@forEach
            if (m.groupValues[2] < dayKey) f.delete()
        }
    }

    private fun file(channelId: Int, dayKey: String) = File(dir, "manifest_${channelId}_$dayKey.json")

    private companion object { val NAME = Regex("""manifest_(\d+)_(\d{4}-\d{2}-\d{2})\.json""") }
}
