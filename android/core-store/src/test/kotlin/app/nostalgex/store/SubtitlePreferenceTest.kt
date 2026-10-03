package app.nostalgex.store

import kotlin.test.Test
import kotlin.test.assertEquals

class SubtitlePreferenceTest {
    @Test fun `defaults to off and persists the choice`() {
        val kv = InMemoryKeyValueStore()
        assertEquals(false, SubtitlePreference(kv).enabled)
        SubtitlePreference(kv).enabled = true
        assertEquals(true, SubtitlePreference(kv).enabled)
        SubtitlePreference(kv).enabled = false
        assertEquals(false, SubtitlePreference(kv).enabled)
    }
}
