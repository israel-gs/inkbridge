package com.inkbridge.data.transport

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.DatagramPacket
import java.net.DatagramSocket

/**
 * Unit tests for [UdpStylusClient].
 *
 * Uses a loopback echo server (DatagramSocket on an ephemeral port) so these
 * tests run without any external infrastructure.
 *
 * transport.md R3: each frame is sent as one datagram.
 * transport.md R6: isConnected transitions, no auto-reconnect.
 */
class UdpStylusClientTest {

    @Test
    fun `connect sets isConnected to true`() = runBlocking {
        val server = DatagramSocket(0) // ephemeral port
        val port = server.localPort
        val client = UdpStylusClient("127.0.0.1", port)
        try {
            val result = client.connect()
            assertTrue(result.isSuccess)
            assertTrue(client.isConnected.value)
        } finally {
            client.close()
            server.close()
        }
    }

    @Test
    fun `send transmits exactly one datagram with correct bytes`() = runBlocking {
        val server = DatagramSocket(0)
        val port = server.localPort
        val client = UdpStylusClient("127.0.0.1", port)
        client.connect()

        val payload = byteArrayOf(0x01, 0x02, 0x03, 0x04)
        val result = client.send(payload)
        assertTrue(result.isSuccess)

        // Receive the datagram on the server side
        val buf = ByteArray(64)
        val packet = DatagramPacket(buf, buf.size)
        server.soTimeout = 2_000
        server.receive(packet)

        val received = buf.copyOf(packet.length)
        assertArrayEquals(payload, received)

        client.close()
        server.close()
    }

    @Test
    fun `close sets isConnected to false`() = runBlocking {
        val server = DatagramSocket(0)
        val port = server.localPort
        val client = UdpStylusClient("127.0.0.1", port)
        client.connect()
        assertTrue(client.isConnected.value)
        client.close()
        assertFalse(client.isConnected.value)
        server.close()
    }

    @Test
    fun `send after close returns failure`() = runBlocking {
        val server = DatagramSocket(0)
        val port = server.localPort
        val client = UdpStylusClient("127.0.0.1", port)
        client.connect()
        client.close()

        val result = client.send(byteArrayOf(0x01))
        assertFalse(result.isSuccess, "send after close must return failure")
        server.close()
    }
}
