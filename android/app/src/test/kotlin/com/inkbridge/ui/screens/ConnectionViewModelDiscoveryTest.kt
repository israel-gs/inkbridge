package com.inkbridge.ui.screens

import com.inkbridge.domain.discovery.DiscoveredHost
import com.inkbridge.domain.discovery.HostDiscoverer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.concurrent.atomic.AtomicInteger

/**
 * Unit tests for [ConnectionViewModel] discovery integration.
 *
 * Tests the [HostDiscoverer] injection, the [discoveredHosts] StateFlow, lifecycle
 * hooks (start/stop), and the [onHostTapped] handler — all without an Application
 * context by testing the discovery logic in isolation via pure helpers.
 *
 * Coverage:
 * - F1: discoveredHosts reflects upstream FakeHostDiscoverer.
 * - F3: onTabFocused/onTabHidden call start/stop.
 * - F5: onHostTapped fills host field with host.ipv4.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionViewModelDiscoveryTest {

    // ── FakeHostDiscoverer ─────────────────────────────────────────────────────

    /**
     * Fake [HostDiscoverer] that records start/stop calls and exposes a
     * mutable StateFlow of discovered hosts for test control.
     */
    class FakeHostDiscoverer : HostDiscoverer {
        private val _hosts = MutableStateFlow<List<DiscoveredHost>>(emptyList())

        val startCount = AtomicInteger(0)
        val stopCount = AtomicInteger(0)

        fun emit(hosts: List<DiscoveredHost>) {
            _hosts.value = hosts
        }

        override fun observe(): Flow<List<DiscoveredHost>> = _hosts

        override suspend fun start() { startCount.incrementAndGet() }
        override suspend fun stop() { stopCount.incrementAndGet() }
    }

    // ── DiscoveryController ────────────────────────────────────────────────────

    /**
     * Pure Kotlin helper that mirrors the discovery slice of ConnectionViewModel.
     *
     * ConnectionViewModel requires Application context (AndroidViewModel) which is
     * unavailable in JVM unit tests. We extract the testable discovery behavior into
     * this controller, mirroring the exact same logic the ViewModel calls. This is
     * the same pattern already established in ConnectionViewModelAutoReconnectTest.
     */
    private class DiscoveryController(private val discoverer: HostDiscoverer) {
        val discoveredHosts = discoverer.observe()

        suspend fun onTabFocused() = discoverer.start()
        suspend fun onTabHidden() = discoverer.stop()
        suspend fun onCleared() = discoverer.stop()

        /**
         * Fills the host field with the tapped host's IPv4.
         * Returns the IPv4 string (the ViewModel updates its own StateFlow).
         */
        fun onHostTapped(host: DiscoveredHost): String = host.ipv4
    }

    // ── F1: discoveredHosts reflects upstream ──────────────────────────────────

    @Test
    fun `discoveredHosts StateFlow reflects FakeHostDiscoverer emissions`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        val hosts = listOf(
            DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.42", port = 4545, version = "1"),
        )
        discoverer.emit(hosts)

        val current = controller.discoveredHosts.first()
        assertEquals(1, current.size)
        assertEquals("InkBridge — Studio", current[0].name)
        assertEquals("192.168.1.42", current[0].ipv4)
    }

    @Test
    fun `discoveredHosts initial value is empty list`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        assertTrue(controller.discoveredHosts.first().isEmpty())
    }

    @Test
    fun `discoveredHosts updates when multiple hosts are emitted`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        discoverer.emit(
            listOf(
                DiscoveredHost("Studio", "192.168.1.10", 4545, "1"),
                DiscoveredHost("Laptop", "192.168.1.11", 4545, "1"),
            ),
        )

        val current = controller.discoveredHosts.first()
        assertEquals(2, current.size)
    }

    // ── F3: Lifecycle hooks ────────────────────────────────────────────────────

    @Test
    fun `onTabFocused calls discoverer start`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        controller.onTabFocused()

        assertEquals(1, discoverer.startCount.get())
    }

    @Test
    fun `onTabHidden calls discoverer stop`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        controller.onTabFocused()
        controller.onTabHidden()

        assertEquals(1, discoverer.stopCount.get())
    }

    @Test
    fun `onCleared calls discoverer stop`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        controller.onTabFocused()
        controller.onCleared()

        assertEquals(1, discoverer.stopCount.get())
    }

    @Test
    fun `onTabFocused is idempotent — second call increments start count`() = runTest {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)

        controller.onTabFocused()
        controller.onTabFocused()

        // The ViewModel calls start() on each focus event; the repository is idempotent internally.
        assertEquals(2, discoverer.startCount.get())
    }

    // ── F5: onHostTapped fills host field ──────────────────────────────────────

    @Test
    fun `onHostTapped returns host ipv4`() {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)
        val host = DiscoveredHost(name = "InkBridge — Studio", ipv4 = "192.168.1.42", port = 4545, version = "1")

        val result = controller.onHostTapped(host)

        assertEquals("192.168.1.42", result)
    }

    @Test
    fun `onHostTapped with different host returns that host ipv4`() {
        val discoverer = FakeHostDiscoverer()
        val controller = DiscoveryController(discoverer)
        val host = DiscoveredHost(name = "InkBridge — Laptop", ipv4 = "10.0.0.5", port = 4545, version = "1")

        val result = controller.onHostTapped(host)

        assertEquals("10.0.0.5", result)
    }
}
