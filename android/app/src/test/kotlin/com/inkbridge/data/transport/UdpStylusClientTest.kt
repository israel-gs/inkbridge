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
    fun `connect sets isConnected to true`() =
        runBlocking {
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
    fun `send transmits exactly one datagram with correct bytes`() =
        runBlocking {
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
    fun `close sets isConnected to false`() =
        runBlocking {
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
    fun `send after close returns failure`() =
        runBlocking {
            val server = DatagramSocket(0)
            val port = server.localPort
            val client = UdpStylusClient("127.0.0.1", port)
            client.connect()
            client.close()

            val result = client.send(byteArrayOf(0x01))
            assertFalse(result.isSuccess, "send after close must return failure")
            server.close()
        }

    /**
     * Buffer-reuse regression: verifies that two sequential sends with different payloads
     * each deliver the correct bytes. Without proper setData() + setLength(), the second
     * send could repeat the first payload or include garbage from the backing buffer.
     */
    @Test
    fun `sequential sends with reused buffer deliver correct distinct payloads`() =
        runBlocking {
            val server = DatagramSocket(0)
            server.soTimeout = 2_000
            val port = server.localPort
            val client = UdpStylusClient("127.0.0.1", port)
            client.connect()

            val payload1 = ByteArray(36) { it.toByte() } // 36 bytes — MOVE frame size
            val payload2 = ByteArray(20) { (it + 100).toByte() } // 20 bytes — PROX/BUTTON size

            client.send(payload1)
            val buf1 = ByteArray(64)
            val pkt1 = DatagramPacket(buf1, buf1.size)
            server.receive(pkt1)
            assertArrayEquals(payload1, buf1.copyOf(pkt1.length), "first reuse-path send must deliver payload1")

            client.send(payload2)
            val buf2 = ByteArray(64)
            val pkt2 = DatagramPacket(buf2, buf2.size)
            server.receive(pkt2)
            assertArrayEquals(payload2, buf2.copyOf(pkt2.length), "second reuse-path send must deliver payload2")

            client.close()
            server.close()
        }

    /**
     * Slow path: payload larger than the 40-byte reuse buffer falls back to a fresh packet.
     */
    @Test
    fun `send with payload larger than reuse buffer uses fallback allocation`() =
        runBlocking {
            val server = DatagramSocket(0)
            server.soTimeout = 2_000
            val port = server.localPort
            val client = UdpStylusClient("127.0.0.1", port)
            client.connect()

            val largePayload = ByteArray(50) { it.toByte() }
            val result = client.send(largePayload)
            assertTrue(result.isSuccess, "oversized payload must still send successfully")

            val buf = ByteArray(128)
            val pkt = DatagramPacket(buf, buf.size)
            server.receive(pkt)
            assertArrayEquals(largePayload, buf.copyOf(pkt.length))

            client.close()
            server.close()
        }
}
