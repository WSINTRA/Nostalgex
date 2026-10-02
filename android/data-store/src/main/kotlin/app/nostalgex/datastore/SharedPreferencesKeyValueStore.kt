package app.nostalgex.datastore

import android.content.Context
import android.content.SharedPreferences
import app.nostalgex.store.KeyValueStore

/**
 * [KeyValueStore] over app-private SharedPreferences. Deliberately thin: all logic lives in
 * core-store where it is unit-tested. NOTE: values are not encrypted at rest (app-private
 * storage only); swap in an encrypted implementation before a public release.
 */
class SharedPreferencesKeyValueStore(private val prefs: SharedPreferences) : KeyValueStore {
    constructor(context: Context, name: String = "nostalgex") : this(context.getSharedPreferences(name, Context.MODE_PRIVATE))

    override fun get(key: String): String? = prefs.getString(key, null)
    override fun put(key: String, value: String) { prefs.edit().putString(key, value).apply() }
    override fun remove(key: String) { prefs.edit().remove(key).apply() }
}
