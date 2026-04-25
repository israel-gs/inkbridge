package com.inkbridge.data.settings

import android.content.SharedPreferences

/**
 * Synchronous settings repository backed by [SharedPreferences].
 *
 * Constructor injection of [SharedPreferences] keeps this class unit-testable
 * without Android instrumentation — callers pass a real SharedPreferences in
 * production and a fake in tests.
 *
 * Key: [KEY_NATURAL_SCROLL] — default true (matches macOS default behaviour).
 */
class SettingsRepository(private val prefs: SharedPreferences) {

    companion object {
        const val KEY_NATURAL_SCROLL = "pref_natural_scroll"
    }

    /**
     * Whether natural scrolling is enabled.
     *
     * When true, two-finger drag moves content in the same direction as the fingers
     * (macOS default). When false, the deltaY is inverted before transmission so the
     * content scrolls in the opposite direction (classic / reverse scrolling).
     */
    var naturalScroll: Boolean
        get() = prefs.getBoolean(KEY_NATURAL_SCROLL, true)
        set(value) = prefs.edit().putBoolean(KEY_NATURAL_SCROLL, value).apply()
}
