package com.inkbridge.data.settings

import android.content.SharedPreferences

/**
 * Minimal in-memory implementation of [SharedPreferences] for unit tests.
 *
 * Only implements the methods used by [SettingsRepository]. Other methods throw
 * [UnsupportedOperationException] to make accidental usage obvious.
 */
class FakeSharedPreferences : SharedPreferences {

    private val map = mutableMapOf<String, Any?>()
    private val listeners = mutableSetOf<SharedPreferences.OnSharedPreferenceChangeListener>()

    inner class FakeEditor : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun apply() {
            map.putAll(pending)
            pending.clear()
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putStringSet(key: String, values: MutableSet<String>?): SharedPreferences.Editor {
            pending[key] = values
            return this
        }

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            pending[key] = null
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            pending.clear()
            map.clear()
            return this
        }
    }

    override fun edit(): SharedPreferences.Editor = FakeEditor()

    override fun getBoolean(key: String, defValue: Boolean): Boolean =
        map.getOrDefault(key, defValue) as? Boolean ?: defValue

    override fun getString(key: String, defValue: String?): String? =
        map.getOrDefault(key, defValue) as? String ?: defValue

    override fun getInt(key: String, defValue: Int): Int =
        map.getOrDefault(key, defValue) as? Int ?: defValue

    override fun getLong(key: String, defValue: Long): Long =
        map.getOrDefault(key, defValue) as? Long ?: defValue

    override fun getFloat(key: String, defValue: Float): Float =
        map.getOrDefault(key, defValue) as? Float ?: defValue

    override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? {
        @Suppress("UNCHECKED_CAST")
        return (map.getOrDefault(key, defValues) as? MutableSet<String>) ?: defValues
    }

    override fun contains(key: String): Boolean = map.containsKey(key)

    override fun getAll(): MutableMap<String, *> = mutableMapOf<String, Any?>().also { it.putAll(map) }

    override fun registerOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) {
        listeners.add(listener)
    }

    override fun unregisterOnSharedPreferenceChangeListener(
        listener: SharedPreferences.OnSharedPreferenceChangeListener,
    ) {
        listeners.remove(listener)
    }
}
