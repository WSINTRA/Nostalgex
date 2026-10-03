package app.nostalgex.store

/** Remembers whether the viewer wants subtitles, across launches. Off until the viewer turns it on. */
class SubtitlePreference(private val store: KeyValueStore) {
    var enabled: Boolean
        get() = store.get(KEY) == "1"
        set(value) { store.put(KEY, if (value) "1" else "0") }

    private companion object { const val KEY = "subtitles_enabled" }
}
