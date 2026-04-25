package com.inkbridge.data.settings

import com.inkbridge.domain.model.TransportKind
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Unit tests for the connection-persistence additions to [SettingsRepository]:
 * lastHost, lastPort, lastTransport, and autoReconnect.
 */
class SettingsRepositoryConnectionTest {

    private lateinit var prefs: FakeSharedPreferences
    private lateinit var repo: SettingsRepository

    @BeforeEach
    fun setUp() {
        prefs = FakeSharedPreferences()
        repo = SettingsRepository(prefs)
    }

    // ── lastHost ──────────────────────────────────────────────────────────────

    @Test
    fun `lastHost defaults to null when nothing stored`() {
        assertNull(repo.lastHost)
    }

    @Test
    fun `lastHost persists and reads back`() {
        repo.lastHost = "192.168.1.50"
        assertEquals("192.168.1.50", repo.lastHost)
    }

    @Test
    fun `lastHost can be cleared by setting to null`() {
        repo.lastHost = "10.0.0.1"
        repo.lastHost = null
        assertNull(repo.lastHost)
    }

    // ── lastPort ──────────────────────────────────────────────────────────────

    @Test
    fun `lastPort defaults to null when nothing stored`() {
        assertNull(repo.lastPort)
    }

    @Test
    fun `lastPort persists and reads back`() {
        repo.lastPort = 4545
        assertEquals(4545, repo.lastPort)
    }

    @Test
    fun `lastPort can be cleared by setting to null`() {
        repo.lastPort = 4545
        repo.lastPort = null
        assertNull(repo.lastPort)
    }

    @Test
    fun `lastPort boundary — minimum valid port 1024`() {
        repo.lastPort = 1024
        assertEquals(1024, repo.lastPort)
    }

    @Test
    fun `lastPort boundary — maximum valid port 65535`() {
        repo.lastPort = 65535
        assertEquals(65535, repo.lastPort)
    }

    // ── lastTransport ─────────────────────────────────────────────────────────

    @Test
    fun `lastTransport defaults to null when nothing stored`() {
        assertNull(repo.lastTransport)
    }

    @Test
    fun `lastTransport persists WIFI_UDP`() {
        repo.lastTransport = TransportKind.WIFI_UDP
        assertEquals(TransportKind.WIFI_UDP, repo.lastTransport)
    }

    @Test
    fun `lastTransport persists USB_TCP`() {
        repo.lastTransport = TransportKind.USB_TCP
        assertEquals(TransportKind.USB_TCP, repo.lastTransport)
    }

    @Test
    fun `lastTransport can be cleared by setting to null`() {
        repo.lastTransport = TransportKind.WIFI_UDP
        repo.lastTransport = null
        assertNull(repo.lastTransport)
    }

    @Test
    fun `lastTransport round-trips via ordinal`() {
        TransportKind.entries.forEach { kind ->
            repo.lastTransport = kind
            assertEquals(kind, repo.lastTransport, "Round-trip failed for $kind")
        }
    }

    // ── autoReconnect ─────────────────────────────────────────────────────────

    @Test
    fun `autoReconnect defaults to true`() {
        assertTrue(repo.autoReconnect)
    }

    @Test
    fun `autoReconnect can be set to false`() {
        repo.autoReconnect = false
        assertFalse(repo.autoReconnect)
    }

    @Test
    fun `autoReconnect can be toggled back to true`() {
        repo.autoReconnect = false
        repo.autoReconnect = true
        assertTrue(repo.autoReconnect)
    }

    @Test
    fun `autoReconnect uses the correct SharedPreferences key`() {
        repo.autoReconnect = false
        assertFalse(prefs.getBoolean(SettingsRepository.KEY_AUTO_RECONNECT, true))
    }

    // ── Compound save — simulates "after successful connect" path ─────────────

    @Test
    fun `saving all connection params persists independently`() {
        repo.lastHost = "172.16.0.5"
        repo.lastPort = 9090
        repo.lastTransport = TransportKind.USB_TCP

        assertEquals("172.16.0.5", repo.lastHost)
        assertEquals(9090, repo.lastPort)
        assertEquals(TransportKind.USB_TCP, repo.lastTransport)
    }
}
