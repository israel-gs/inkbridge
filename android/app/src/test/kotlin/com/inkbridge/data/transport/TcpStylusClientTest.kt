package com.inkbridge.data.transport

import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.ServerSocket

/**
 * Unit tests for [TcpStylusClient].
 *
 * Uses a loopback ServerSocket on an ephemeral port to avoid needing a real macOS server.
 *
 * transport.md R4: TCP connection with TCP_NODELAY, 3-second timeout.
 * transport.md R6: state transitions, no auto-reconnect.
 */
class TcpStylusClientTest {

    @Test
    fun `connect sets isConnected to true`() = runBlocking {
        val server = ServerSocket(0) // ephemeral port
        val port = server.localPort
        // Accept in a separate thread to avoid deadlock with the blocking accept() call
        val acceptThread = Thread {
            runCatching { server.accept() }
        }
        acceptThread.start()

        val client = TcpStylusClient("127.0.0.1", port)
        try {
            val result = client.connect()
            assertTrue(result.isSuccess, "connect must succeed: ${result.exceptionOrNull()}")
            assertTrue(client.isConnected.value)
        } finally {
            client.close()
            server.close()
        }
    }

    @Test
    fun `send transmits bytes that are received by the server`() = runBlocking {
        val server = ServerSocket(0)
        val port = server.localPort
        var receivedBytes: ByteArray? = null

        val acceptThread = Thread {
            val conn = server.accept()
            val buf = ByteArray(64)
            val n = conn.getInputStream().read(buf)
            receivedBytes = buf.copyOf(n)
            conn.close()
        }
        acceptThread.start()

        val client = TcpStylusClient("127.0.0.1", port)
        client.connect()

        val payload = byteArrayOf(0x01, 0x02, 0x03, 0x04, 0x05)
        val result = client.send(payload)
        assertTrue(result.isSuccess)

        acceptThread.join(3_000)
        assertArrayEquals(payload, receivedBytes, "Server must receive exactly the sent bytes")

        client.close()
        server.close()
    }

    @Test
    fun `close sets isConnected to false`() = runBlocking {
        val server = ServerSocket(0)
        val port = server.localPort
        val acceptThread = Thread { runCatching { server.accept() } }
        acceptThread.start()

        val client = TcpStylusClient("127.0.0.1", port)
        client.connect()
        assertTrue(client.isConnected.value)
        client.close()
        assertFalse(client.isConnected.value)
        server.close()
    }

    @Test
    fun `send after close returns failure`() = runBlocking {
        val server = ServerSocket(0)
        val port = server.localPort
        val acceptThread = Thread { runCatching { server.accept() } }
        acceptThread.start()

        val client = TcpStylusClient("127.0.0.1", port)
        client.connect()
        client.close()

        val result = client.send(byteArrayOf(0x01))
        assertFalse(result.isSuccess, "send after close must return failure")
        server.close()
    }

    @Test
    fun `connect to refused port returns failure`() = runBlocking {
        // Port 1 is almost certainly refused and not in use
        val client = TcpStylusClient("127.0.0.1", 1)
        val result = client.connect()
        assertFalse(result.isSuccess, "connect to refused port must return failure")
        assertFalse(client.isConnected.value)
    }

    // ── Bug 3: send failure emits to errors and sets isConnected=false ─────────

    /**
     * When [TcpStylusClient.send] fails (e.g. broken pipe after server dies),
     * [isConnected] must transition to false AND the cause must be emitted to
     * [errors] so [ConnectionManager] can detect mid-session disconnects.
     */
    @Test
    fun `send failure sets isConnected to false and emits to errors`() = runBlocking {
        val server = ServerSocket(0)
        val port = server.localPort
        var serverConn: java.net.Socket? = null
        val acceptThread = Thread {
            runCatching { serverConn = server.accept() }
        }
        acceptThread.start()

        val client = TcpStylusClient("127.0.0.1", port)
        client.connect()
        assertTrue(client.isConnected.value)
        acceptThread.join(3_000)

        // Collect the first error asynchronously.
        val errorDeferred = async { client.errors.first() }

        // Abruptly close the server-side socket to cause a broken pipe on next write.
        serverConn?.close()
        server.close()

        // Write enough data to trigger a broken-pipe flush. TCP may buffer small
        // writes, so we retry until the OS delivers the RST.
        var failureResult: Result<Unit> = Result.success(Unit)
        val bigPayload = ByteArray(65536) { 0x01 }
        repeat(5) {
            if (failureResult.isSuccess) {
                failureResult = client.send(bigPayload)
                // Small delay to give the kernel time to process the RST.
                @Suppress("BlockingMethodInNonBlockingContext")
                Thread.sleep(50)
            }
        }

        // Await the error with a reasonable timeout.
        val error = kotlinx.coroutines.withTimeoutOrNull(2_000) { errorDeferred.await() }
        assertNotNull(error, "errors flow must emit a Throwable after send failure")
        assertFalse(client.isConnected.value, "isConnected must be false after send failure")
    }
}
