package com.inkbridge.data.connection

import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.domain.model.TransportKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Unit tests for [ConnectionManager] using [FakeTransport].
 *
 * Verifies state transitions per transport.md R6:
 *   Disconnected → Connecting → Connected(kind) | Error(reason)
 *   Connected → Disconnected (on disconnect())
 *
 * USB_TCP must pin host to 127.0.0.1 (transport.md R4).
 */
class ConnectionManagerTest {

    // ── Fake transport ────────────────────────────────────────────────────────

    private class FakeTransport(
        private val connectResult: Result<Unit> = Result.success(Unit),
    ) : StylusTransport {
        private val _isConnected = MutableStateFlow(false)
        override val isConnected: StateFlow<Boolean> = _isConnected

        var connectCalled = false
        var closeCalled = false
        var lastHost: String? = null
        var lastPort: Int? = null

        override suspend fun connect(): Result<Unit> {
            connectCalled = true
            if (connectResult.isSuccess) _isConnected.value = true
            return connectResult
        }

        override suspend fun send(bytes: ByteArray): Result<Unit> = Result.success(Unit)

        override suspend fun close() {
            closeCalled = true
            _isConnected.value = false
        }
    }

    private fun makeManager(
        fakeTransport: FakeTransport,
        captureHost: Boolean = false,
        capturePort: Boolean = false,
    ): ConnectionManager {
        val factory = ConnectionManager.TransportFactory { host, port, _ ->
            fakeTransport.lastHost = host
            fakeTransport.lastPort = port
            fakeTransport
        }
        return ConnectionManager(factory)
    }

    // ── State transitions ─────────────────────────────────────────────────────

    @Test
    fun `initial state is Disconnected`() {
        val manager = ConnectionManager()
        assertEquals(ConnectionState.Disconnected, manager.state.value)
    }

    @Test
    fun `successful connect transitions to Connected`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)

        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        assertEquals(ConnectionState.Connected(TransportKind.WIFI_UDP), manager.state.value)
    }

    @Test
    fun `failed connect transitions to Error`() = runBlocking {
        val fake = FakeTransport(Result.failure(Exception("refused")))
        val manager = makeManager(fake)

        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        val state = manager.state.value
        assertTrue(state is ConnectionState.Error)
        assertTrue((state as ConnectionState.Error).reason.contains("refused"))
    }

    @Test
    fun `disconnect from Connected transitions to Disconnected`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)

        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        assertEquals(ConnectionState.Connected(TransportKind.WIFI_UDP), manager.state.value)

        manager.disconnect()
        assertEquals(ConnectionState.Disconnected, manager.state.value)
    }

    @Test
    fun `disconnect calls close on active transport`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)

        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        manager.disconnect()

        assertTrue(fake.closeCalled, "close() must be called on disconnect")
    }

    @Test
    fun `currentTransport is null before connect`() {
        val manager = ConnectionManager()
        assertNull(manager.currentTransport())
    }

    @Test
    fun `currentTransport is non-null after successful connect`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)
        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        assertTrue(manager.currentTransport() != null)
    }

    @Test
    fun `currentTransport is null after disconnect`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)
        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)
        manager.disconnect()
        assertNull(manager.currentTransport())
    }

    // ── USB_TCP host pinning ──────────────────────────────────────────────────

    @Test
    fun `USB_TCP connect uses 127,0,0,1 regardless of provided host`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)

        manager.connect("10.0.0.5", 4545, TransportKind.USB_TCP)

        assertEquals("127.0.0.1", fake.lastHost, "USB_TCP must pin host to 127.0.0.1")
        assertEquals(ConnectionState.Connected(TransportKind.USB_TCP), manager.state.value)
    }

    @Test
    fun `WIFI_UDP connect uses the provided host`() = runBlocking {
        val fake = FakeTransport(Result.success(Unit))
        val manager = makeManager(fake)

        manager.connect("192.168.1.100", 4545, TransportKind.WIFI_UDP)

        assertEquals("192.168.1.100", fake.lastHost)
    }

    // ── Error path: transport is closed on failed connect ─────────────────────

    @Test
    fun `failed connect closes the transport`() = runBlocking {
        val fake = FakeTransport(Result.failure(Exception("refused")))
        val manager = makeManager(fake)

        manager.connect("192.168.1.1", 4545, TransportKind.WIFI_UDP)

        assertTrue(fake.closeCalled, "Transport must be closed after failed connect")
    }
}
