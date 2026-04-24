package com.inkbridge.data.transport

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertFalse
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
}
