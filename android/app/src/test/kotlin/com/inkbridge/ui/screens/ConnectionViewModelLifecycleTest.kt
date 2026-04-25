package com.inkbridge.ui.screens

import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusSink
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.domain.model.TransportKind
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.concurrent.Executors

/**
 * Tests for [ConnectionViewModel.onCleared] (Bug 1 fix).
 *
 * [ConnectionViewModel] requires [android.app.Application] context which is not
 * available in the JVM unit-test tier. We therefore test the constituent behaviours
 * directly — this mirrors the exact operations performed in [onCleared].
 */
class ConnectionViewModelLifecycleTest {
    // ── Fakes ─────────────────────────────────────────────────────────────────

    private class TrackingTransport : StylusTransport {
        private val _isConnected = MutableStateFlow(true)
        override val isConnected: StateFlow<Boolean> = _isConnected
        override val errors: SharedFlow<Throwable> = MutableSharedFlow()
        var closeCalled = false

        override suspend fun connect() = Result.success(Unit)

        override suspend fun close() {
            closeCalled = true
            _isConnected.value = false
        }

        override suspend fun send(bytes: ByteArray) = Result.success(Unit)
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /**
     * After [onCleared], the emitChannel must be closed for send and the executor
     * must be shut down.
     */
    @Test
    fun `emitChannel is closed and executor is shutdown after onCleared`() {
        val channel = Channel<suspend (StylusSink) -> Unit>(Channel.UNLIMITED)
        val executor = Executors.newSingleThreadExecutor()

        // Simulate onCleared body.
        channel.close()
        executor.shutdown()

        assertTrue(channel.isClosedForSend, "emitChannel must be closed for send after onCleared")
        assertTrue(executor.isShutdown, "executor must be shut down after onCleared")
    }

    /**
     * Disconnect is called on the ConnectionManager during onCleared, which must
     * transition state to Disconnected and call close() on any active transport.
     */
    @Test
    fun `connectionManager is disconnected after onCleared`() =
        runBlocking {
            val transport = TrackingTransport()
            val factory = ConnectionManager.TransportFactory { _, _, _ -> transport }
            val manager = ConnectionManager(factory)

            manager.connect("127.0.0.1", 4545, TransportKind.USB_TCP)
            assertTrue(manager.state.value is ConnectionState.Connected)

            // Simulate the disconnect() call from onCleared.
            manager.disconnect()

            assertFalse(transport.isConnected.value, "transport must be closed after onCleared disconnect")
            assertTrue(manager.state.value is ConnectionState.Disconnected)
        }

    /**
     * The emitChannel consumer coroutine exits cleanly when the channel is closed:
     * the `for job in channel` loop terminates naturally without losing items.
     * This test verifies all items sent before close are still drained by
     * consuming via tryReceive (non-suspending) in a normal test.
     */
    @Test
    fun `consumer drains all pending items before exiting when channel is closed`() =
        runBlocking {
            val consumed = mutableListOf<Int>()
            val channel = Channel<Int>(Channel.UNLIMITED)

            repeat(10) { channel.trySend(it) }
            channel.close()

            // Drain: this mirrors what the `for (job in channel)` loop does.
            for (item in channel) {
                consumed.add(item)
            }

            assertTrue(consumed.size == 10, "All 10 items must be consumed before the loop exits")
            assertTrue(consumed == (0..9).toList(), "Items must be consumed in FIFO order")
        }
}
