package com.inkbridge.data.settings

import android.content.SharedPreferences
import com.inkbridge.domain.model.TransportKind

/**
 * Synchronous settings repository backed by [SharedPreferences].
 *
 * Constructor injection of [SharedPreferences] keeps this class unit-testable
 * without Android instrumentation — callers pass a real SharedPreferences in
 * production and a fake in tests.
 *
 * Keys:
 * - [KEY_NATURAL_SCROLL] — default true (matches macOS default behaviour).
 * - [KEY_LAST_HOST] — last successfully connected host (null = never connected).
 * - [KEY_LAST_PORT] — last successfully connected port (0 = never connected).
 * - [KEY_LAST_TRANSPORT] — ordinal of last [TransportKind] (-1 = never connected).
 * - [KEY_AUTO_RECONNECT] — whether auto-reconnect is enabled (default true).
 */
class SettingsRepository(private val prefs: SharedPreferences) {
    companion object {
        const val KEY_NATURAL_SCROLL = "pref_natural_scroll"
        const val KEY_LAST_HOST = "pref_last_host"
        const val KEY_LAST_PORT = "pref_last_port"
        const val KEY_LAST_TRANSPORT = "pref_last_transport"
        const val KEY_AUTO_RECONNECT = "pref_auto_reconnect"
        const val KEY_HAPTIC_INTENSITY = "pref_haptic_intensity"
        const val KEY_CLICK_FLASH = "pref_click_flash"
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

    /** Last successfully connected host, or null if never connected. */
    var lastHost: String?
        get() = prefs.getString(KEY_LAST_HOST, null)
        set(value) =
            if (value != null) {
                prefs.edit().putString(KEY_LAST_HOST, value).apply()
            } else {
                prefs.edit().remove(KEY_LAST_HOST).apply()
            }

    /** Last successfully connected port, or null if never connected. */
    var lastPort: Int?
        get() {
            val stored = prefs.getInt(KEY_LAST_PORT, -1)
            return if (stored == -1) null else stored
        }
        set(value) =
            if (value != null) {
                prefs.edit().putInt(KEY_LAST_PORT, value).apply()
            } else {
                prefs.edit().putInt(KEY_LAST_PORT, -1).apply()
            }

    /** Last successfully connected [TransportKind], or null if never connected. */
    var lastTransport: TransportKind?
        get() {
            val ordinal = prefs.getInt(KEY_LAST_TRANSPORT, -1)
            return if (ordinal == -1) null else TransportKind.entries.getOrNull(ordinal)
        }
        set(value) =
            if (value != null) {
                prefs.edit().putInt(KEY_LAST_TRANSPORT, value.ordinal).apply()
            } else {
                prefs.edit().putInt(KEY_LAST_TRANSPORT, -1).apply()
            }

    /**
     * Whether auto-reconnect is enabled.
     *
     * When true, [ConnectionViewModel] retries automatically on [ConnectionState.Error]
     * if saved connection params exist.
     */
    var autoReconnect: Boolean
        get() = prefs.getBoolean(KEY_AUTO_RECONNECT, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_RECONNECT, value).apply()

    /**
     * Haptic feedback intensity, 0-100. 0 = disabled, 100 = max amplitude.
     * Mapped to [VibrationEffect] amplitude in [InkBridgeApp].
     * Default 100 — most Samsung tablets need full amplitude to be perceptible
     * because the vibrator's max physical output is already modest.
     */
    var hapticIntensity: Int
        get() = prefs.getInt(KEY_HAPTIC_INTENSITY, 100).coerceIn(0, 100)
        set(value) = prefs.edit().putInt(KEY_HAPTIC_INTENSITY, value.coerceIn(0, 100)).apply()

    /** Whether to render a visual ripple at the click point. */
    var clickFlashEnabled: Boolean
        get() = prefs.getBoolean(KEY_CLICK_FLASH, true)
        set(value) = prefs.edit().putBoolean(KEY_CLICK_FLASH, value).apply()
}
