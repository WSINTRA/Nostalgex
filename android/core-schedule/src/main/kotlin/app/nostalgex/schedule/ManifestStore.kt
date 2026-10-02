package app.nostalgex.schedule

data class StoredBlock(val id: String, val startEpochSec: Long, val endEpochSec: Long)

/** One persisted channel-day. [poolFingerprint] invalidates it when the pool changes. */
data class StoredDay(val dayKey: String, val poolFingerprint: String, val blocks: List<StoredBlock>)

/** Persistence seam for daily manifests (tvOS: DailyManifestStore). */
interface ManifestStore {
    fun load(channelId: Int, dayKey: String): StoredDay?
    fun save(channelId: Int, day: StoredDay)
}

class InMemoryManifestStore : ManifestStore {
    private val days = HashMap<Pair<Int, String>, StoredDay>()
    override fun load(channelId: Int, dayKey: String) = days[channelId to dayKey]
    override fun save(channelId: Int, day: StoredDay) { days[channelId to day.dayKey] = day }
}
