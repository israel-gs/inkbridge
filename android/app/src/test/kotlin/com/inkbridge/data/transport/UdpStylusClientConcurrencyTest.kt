package com.inkbridge.data.transport

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.net.DatagramPacket
import java.net.DatagramSocket

/**
 * Concurrency tests for [UdpStylusClient.send].
 *
 * Bug 2 fix: [send] is serialised by an internal [kotlinx.coroutines.sync.Mutex]
 * so concurrent callers cannot race on the reuse buffer.
 *
 * We fire 4 concurrent [send] calls from [Dispatchers.IO] and verify that all
 * datagrams are received correctly by a loopback server.
 */
class UdpStylusClientConcurrencyTest {
    @Test
    fun `concurrent sends from 4 coroutines all deliver correct bytes`() =
        runBlocking {
            val server = DatagramSocket(0)
            server.soTimeout = 5_000
            val port = server.localPort
            val client = UdpStylusClient("127.0.0.1", port)
            client.connect()

            // 4 distinct payloads — each must arrive intact with no corruption.
            val payloads = (0 until 4).map { i -> ByteArray(20) { (i * 10 + it).toByte() } }

            // Launch 4 coroutines concurrently on Dispatchers.IO.
            val results =
                payloads.map { payload ->
                    async(Dispatchers.IO) { client.send(payload) }
                }.awaitAll()

            // All sends must succeed.
            results.forEach { assertTrue(it.isSuccess, "All sends must succeed, got: $it") }

            // Collect all received datagrams.
            val received = mutableListOf<ByteArray>()
            repeat(4) {
                val buf = ByteArray(64)
                val pkt = DatagramPacket(buf, buf.size)
                server.receive(pkt)
                received.add(buf.copyOf(pkt.length))
            }

            // All 4 payloads must appear in the received set (order may vary).
            assertEquals(4, received.size, "Must receive exactly 4 datagrams")
            payloads.forEach { expected ->
                assertTrue(
                    received.any { it.contentEquals(expected) },
                    "Payload ${expected.toList()} not found in received set",
                )
            }

            client.close()
            server.close()
        }

    @Test
    fun `concurrent sends produce no corrupted datagrams`() =
        runBlocking {
            val server = DatagramSocket(0)
            server.soTimeout = 5_000
            val port = server.localPort
            val client = UdpStylusClient("127.0.0.1", port)
            client.connect()

            // Use 36-byte payloads (MOVE frame size) to stress the reuse-buffer path.
            val payloads = (0 until 4).map { i -> ByteArray(36) { i.toByte() } }

            payloads.map { payload ->
                async(Dispatchers.IO) { client.send(payload) }
            }.awaitAll()

            // Verify each datagram's bytes are uniform (no cross-contamination).
            repeat(4) {
                val buf = ByteArray(64)
                val pkt = DatagramPacket(buf, buf.size)
                server.receive(pkt)
                val data = buf.copyOf(pkt.length)
                assertEquals(36, data.size, "Datagram size must be 36")
                // All bytes in the datagram must have the same value (one of 0..3).
                val unique = data.toSet()
                assertEquals(
                    1,
                    unique.size,
                    "Datagram must not contain mixed bytes from concurrent sends; found: $unique",
                )
            }

            client.close()
            server.close()
        }
}
