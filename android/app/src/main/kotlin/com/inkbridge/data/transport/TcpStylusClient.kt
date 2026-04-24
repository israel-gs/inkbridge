package com.inkbridge.data.transport

import com.inkbridge.domain.model.StylusTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * TCP transport — streams encoded wire frames over a loopback connection (transport.md R4).
 *
 * Frame framing: raw contiguous byte writes. The macOS receiver reads the 16-byte header
 * first, then the payload length determined by event_type (transport.md R4, wire-protocol.md R3).
 * No additional length-prefix framing is applied on the Android side — the codec frame
 * is self-describing via event_type (wire-protocol.md R3–R4).
 *
 * RISK: The apply brief suggested a u16 LE length-prefix framing. The spec (transport.md R4)
 * says "Frames MUST be written to the TCP stream as contiguous byte sequences" and instructs
 * the receiver to use the header's event_type to determine payload length. Raw writes (no
 * length prefix) are therefore the spec-compliant implementation. Flagged for review.
 *
 * Settings: TCP_NODELAY=true (latency), keep-alive=true (transport.md R4 design).
 * Connect timeout: 3 seconds per transport.md R4.
 * No auto-reconnect (transport.md R6).
 *
 * @param host Remote host (should be 127.0.0.1 for USB path — transport.md R4).
 * @param port Remote port. Default 4545 (transport.md R1).
 */
class TcpStylusClient(
    private val host: String = "127.0.0.1",
    private val port: Int = 4545,
) : StylusTransport {

    private val _isConnected = MutableStateFlow(false)
    override val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    @Volatile
    private var socket: Socket? = null

    @Volatile
    private var outputStream: OutputStream? = null

    override suspend fun connect(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val sock = Socket()
            sock.tcpNoDelay = true
            sock.keepAlive = true
            sock.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            outputStream = sock.getOutputStream()
            socket = sock
            _isConnected.value = true
        }
    }

    override suspend fun send(bytes: ByteArray): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val out = outputStream ?: error("Not connected")
            out.write(bytes)
            out.flush()
        }
    }

    override suspend fun close() = withContext(Dispatchers.IO) {
        _isConnected.value = false
        try {
            outputStream?.close()
        } catch (_: Exception) {}
        try {
            socket?.close()
        } catch (_: Exception) {}
        outputStream = null
        socket = null
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 3_000
    }
}
