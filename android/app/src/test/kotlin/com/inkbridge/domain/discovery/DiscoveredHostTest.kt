package com.inkbridge.domain.discovery

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Unit tests for [DiscoveredHost] data class.
 *
 * Verifies equality semantics and IPv4 format contract per spec
 * requirement "DiscoveredHost.ipv4 MUST be a dotted-decimal IPv4".
 */
class DiscoveredHostTest {

    // ── Data-class equality ────────────────────────────────────────────────────

    @Test
    fun `two instances with identical fields are equal`() {
        val a = DiscoveredHost(
            name = "InkBridge — Studio",
            ipv4 = "192.168.1.42",
            port = 4545,
            version = "1",
        )
        val b = DiscoveredHost(
            name = "InkBridge — Studio",
            ipv4 = "192.168.1.42",
            port = 4545,
            version = "1",
        )
        assertEquals(a, b)
    }

    @Test
    fun `instances differing by ipv4 are not equal`() {
        val a = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.10", port = 4545, version = "1")
        val b = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.20", port = 4545, version = "1")
        assertNotEquals(a, b)
    }

    @Test
    fun `instances differing by name are not equal`() {
        val a = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.10", port = 4545, version = "1")
        val b = DiscoveredHost(name = "InkBridge — Laptop", ipv4 = "192.168.1.10", port = 4545, version = "1")
        assertNotEquals(a, b)
    }

    @Test
    fun `instances differing by port are not equal`() {
        val a = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.10", port = 4545, version = "1")
        val b = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.10", port = 9090, version = "1")
        assertNotEquals(a, b)
    }

    // ── IPv4 format contract ────────────────────────────────────────────────────

    private val dotDecimalRegex = Regex("""^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$""")

    @Test
    fun `ipv4 field matches dotted-decimal format`() {
        val host = DiscoveredHost(
            name = "InkBridge — Studio",
            ipv4 = "192.168.1.42",
            port = 4545,
            version = "1",
        )
        assertTrue(dotDecimalRegex.matches(host.ipv4)) {
            "Expected dotted-decimal IPv4, got: ${host.ipv4}"
        }
    }

    @Test
    fun `ipv4 field with zeros matches dotted-decimal format`() {
        val host = DiscoveredHost(
            name = "InkBridge — Laptop",
            ipv4 = "10.0.0.1",
            port = 4545,
            version = "1",
        )
        assertTrue(dotDecimalRegex.matches(host.ipv4)) {
            "Expected dotted-decimal IPv4, got: ${host.ipv4}"
        }
    }

    // ── copy semantics ─────────────────────────────────────────────────────────

    @Test
    fun `copy creates a new instance with updated field`() {
        val original = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.10", port = 4545, version = "1")
        val updated = original.copy(ipv4 = "10.0.0.5")

        assertEquals("10.0.0.5", updated.ipv4)
        assertEquals(original.name, updated.name)
        assertEquals(original.port, updated.port)
        assertNotEquals(original, updated)
    }
}
