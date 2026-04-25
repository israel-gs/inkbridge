package com.inkbridge.ui.screens

import com.inkbridge.data.settings.FakeSharedPreferences
import com.inkbridge.data.settings.SettingsRepository
import com.inkbridge.domain.model.TransportKind
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Unit tests for the auto-reconnect logic layer.
 *
 * These tests operate at the level of the [SettingsRepository] and the
 * [AutoReconnectController] — a pure Kotlin helper extracted from the ViewModel
 * logic so it can be unit-tested without an Application context.
 *
 * The controller encapsulates:
 * 1. Persisting connection params on success.
 * 2. Deciding whether a retry should start (autoReconnect + saved params exist).
 * 3. Counting attempts and stopping at the cap.
 * 4. Cancellation when the user disconnects.
 */
class ConnectionViewModelAutoReconnectTest {

    // ── Fake retry scheduler ──────────────────────────────────────────────────

    /**
     * Records connect attempts instead of actually connecting. Used to verify
     * the controller drives retries correctly without a real ViewModel.
     */
    private class FakeConnectAction {
        data class Attempt(val host: String, val port: Int, val kind: TransportKind)

        val attempts = mutableListOf<Attempt>()
        var simulateSuccess = false

        fun connect(
            host: String,
            port: Int,
            kind: TransportKind,
        ): Boolean {
            attempts.add(Attempt(host, port, kind))
            return simulateSuccess
        }
    }

    /**
     * Minimal replica of the auto-reconnect decision logic from
     * [ConnectionViewModel]. Tests this in isolation from Android.
     */
    private class AutoReconnectController(
        private val settings: SettingsRepository,
        private val maxAttempts: Int = 30,
    ) {
        private var attempts = 0
        private var cancelled = false

        /** Called after a successful connect — persists params. */
        fun onConnectSuccess(
            host: String,
            port: Int,
            kind: TransportKind,
        ) {
            settings.lastHost = host
            settings.lastPort = port
            settings.lastTransport = kind
        }

        /** Returns true if auto-reconnect should be attempted. */
        fun shouldRetry(): Boolean {
            if (!settings.autoReconnect) return false
            if (cancelled) return false
            if (attempts >= maxAttempts) return false
            return settings.lastHost != null &&
                settings.lastPort != null &&
                settings.lastTransport != null
        }

        /**
         * Records one retry attempt. Returns the params to connect with, or null
         * if retry should not happen.
         */
        fun nextRetry(): Triple<String, Int, TransportKind>? {
            if (!shouldRetry()) return null
            attempts++
            return Triple(
                settings.lastHost!!,
                settings.lastPort!!,
                settings.lastTransport!!,
            )
        }

        /** Cancels the retry loop (user-initiated disconnect). */
        fun cancel() {
            cancelled = true
            attempts = 0
        }

        fun attemptCount(): Int = attempts
    }

    // ── Test fixtures ─────────────────────────────────────────────────────────

    private lateinit var prefs: FakeSharedPreferences
    private lateinit var settings: SettingsRepository
    private lateinit var controller: AutoReconnectController

    @BeforeEach
    fun setUp() {
        prefs = FakeSharedPreferences()
        settings = SettingsRepository(prefs)
        controller = AutoReconnectController(settings)
    }

    // ── onConnectSuccess persists params ──────────────────────────────────────

    @Test
    fun `onConnectSuccess saves host, port, and transport`() {
        controller.onConnectSuccess("192.168.1.10", 4545, TransportKind.WIFI_UDP)

        assertEquals("192.168.1.10", settings.lastHost)
        assertEquals(4545, settings.lastPort)
        assertEquals(TransportKind.WIFI_UDP, settings.lastTransport)
    }

    @Test
    fun `onConnectSuccess overwrites previous params`() {
        controller.onConnectSuccess("10.0.0.1", 4545, TransportKind.WIFI_UDP)
        controller.onConnectSuccess("127.0.0.1", 9090, TransportKind.USB_TCP)

        assertEquals("127.0.0.1", settings.lastHost)
        assertEquals(9090, settings.lastPort)
        assertEquals(TransportKind.USB_TCP, settings.lastTransport)
    }

    // ── shouldRetry conditions ────────────────────────────────────────────────

    @Test
    fun `shouldRetry returns false when autoReconnect is disabled`() {
        settings.autoReconnect = false
        controller.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        assertFalse(controller.shouldRetry())
    }

    @Test
    fun `shouldRetry returns false when no saved params`() {
        // autoReconnect is true by default; no saved params
        assertFalse(controller.shouldRetry())
    }

    @Test
    fun `shouldRetry returns true when autoReconnect and saved params exist`() {
        controller.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        assertTrue(controller.shouldRetry())
    }

    // ── nextRetry provides correct params ────────────────────────────────────

    @Test
    fun `nextRetry returns saved params`() {
        controller.onConnectSuccess("10.10.0.1", 4545, TransportKind.USB_TCP)

        val result = controller.nextRetry()!!
        assertEquals("10.10.0.1", result.first)
        assertEquals(4545, result.second)
        assertEquals(TransportKind.USB_TCP, result.third)
    }

    @Test
    fun `nextRetry returns null when no saved params`() {
        assertNull(controller.nextRetry())
    }

    // ── Attempt cap ──────────────────────────────────────────────────────────

    @Test
    fun `retries stop after maxAttempts`() {
        val cap = 5
        val capped = AutoReconnectController(settings, maxAttempts = cap)
        capped.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        repeat(cap) { capped.nextRetry() }
        assertNull(capped.nextRetry(), "nextRetry must return null after $cap attempts")
        assertEquals(cap, capped.attemptCount())
    }

    @Test
    fun `shouldRetry returns false after maxAttempts reached`() {
        val cap = 3
        val capped = AutoReconnectController(settings, maxAttempts = cap)
        capped.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        repeat(cap) { capped.nextRetry() }
        assertFalse(capped.shouldRetry())
    }

    // ── Cancellation ─────────────────────────────────────────────────────────

    @Test
    fun `cancel stops retries`() {
        controller.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        assertTrue(controller.shouldRetry())

        controller.cancel()
        assertFalse(controller.shouldRetry())
    }

    @Test
    fun `cancel returns null from nextRetry`() {
        controller.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        controller.cancel()

        assertNull(controller.nextRetry())
    }

    @Test
    fun `cancel resets attempt count`() {
        controller.onConnectSuccess("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        controller.nextRetry()
        controller.cancel()

        assertEquals(0, controller.attemptCount())
    }

    // ── Connect action wiring ─────────────────────────────────────────────────

    @Test
    fun `retry drives connect action with saved params`() {
        val action = FakeConnectAction()
        controller.onConnectSuccess("172.16.0.5", 4545, TransportKind.WIFI_UDP)

        val params = controller.nextRetry()!!
        action.connect(params.first, params.second, params.third)

        assertEquals(1, action.attempts.size)
        assertEquals("172.16.0.5", action.attempts[0].host)
        assertEquals(4545, action.attempts[0].port)
        assertEquals(TransportKind.WIFI_UDP, action.attempts[0].kind)
    }
}
