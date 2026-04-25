package com.inkbridge.data.transport

import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.protocol.BinaryStylusCodec
import com.inkbridge.protocol.DecodedFrame
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * TCP transport — streams encoded wire frames over a loopback connection (transport.md R4).
 *
 * Bidirectional: outbound writes via [send]; inbound reads run in a background
 * coroutine that reassembles frames from the byte stream and exposes them via
 * [incomingFrames]. Inbound is used for control-plane messages like
 * `CAPTURE_RESPONSE` (Mac → tablet).
 *
 * Frame framing: raw contiguous byte writes. The receiver (each side) reads the
 * 16-byte header first, then the payload length determined by event_type
 * (transport.md R4, wire-protocol.md R3).
 */
class TcpStylusClient(
    private val host: String = "127.0.0.1",
    private val port: Int = 4545,
) : StylusTransport {
    private val _isConnected = MutableStateFlow(false)
    override val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private val _errors = MutableSharedFlow<Throwable>(extraBufferCapacity = 1)
    override val errors: SharedFlow<Throwable> = _errors.asSharedFlow()

    private val _incoming = MutableSharedFlow<DecodedFrame>(extraBufferCapacity = 16)
    override val incomingFrames: SharedFlow<DecodedFrame> = _incoming.asSharedFlow()

    @Volatile private var socket: Socket? = null
    @Volatile private var outputStream: OutputStream? = null
    @Volatile private var readJob: Job? = null

    private val readScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override suspend fun connect(): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                val sock = Socket()
                sock.tcpNoDelay = true
                sock.keepAlive = true
                sock.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                outputStream = sock.getOutputStream()
                socket = sock
                _isConnected.value = true
                // Spawn the read loop. Cancelled in [close].
                readJob = readScope.launch {
                    runReadLoop(sock.getInputStream())
                }
            }
        }

    override suspend fun send(bytes: ByteArray): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                val out = outputStream ?: error("Not connected")
                out.write(bytes)
                out.flush()
            }.also { result ->
                result.exceptionOrNull()?.let { cause ->
                    if (_isConnected.value) {
                        _isConnected.value = false
                        _errors.tryEmit(cause)
                    }
                }
            }
        }

    override suspend fun close() =
        withContext(Dispatchers.IO) {
            _isConnected.value = false
            readJob?.cancel()
            readJob = null
            try { outputStream?.close() } catch (_: Exception) {}
            try { socket?.close() } catch (_: Exception) {}
            outputStream = null
            socket = null
        }

    /**
     * Reads from [input] forever, reassembling frames using the event_type →
     * payload-size table. Mirrors the Mac-side TCPListener.drainFrames.
     */
    private suspend fun runReadLoop(input: InputStream) {
        val buffer = ByteArray(MAX_FRAME_SIZE * 4)
        var len = 0
        try {
            while (true) {
                val read = input.read(buffer, len, buffer.size - len)
                if (read <= 0) break
                len += read
                len = drainFrames(buffer, len)
            }
        } catch (_: Throwable) {
            // Read failed — likely socket closed. Mirror to errors stream so
            // the connection layer knows.
            if (_isConnected.value) {
                _isConnected.value = false
            }
        }
    }

    /**
     * Consumes complete frames from the head of [buffer] up to [length],
     * emits them, and shifts any partial trailing bytes back to the start.
     * Returns the new valid byte count.
     */
    private suspend fun drainFrames(buffer: ByteArray, length: Int): Int {
        var consumed = 0
        while (length - consumed >= HEADER_SIZE) {
            val eventType = buffer[consumed + 1].toInt() and 0xFF
            val payloadSize = payloadSizeFor(eventType) ?: run {
                // Unknown type. Discard the entire buffered window and resync
                // on the next read — same strategy as the Mac side.
                return 0
            }
            val frameSize = HEADER_SIZE + payloadSize
            if (length - consumed < frameSize) break

            val frame = ByteArray(frameSize)
            System.arraycopy(buffer, consumed, frame, 0, frameSize)
            try {
                val decoded = BinaryStylusCodec.decode(frame)
                _incoming.emit(decoded)
            } catch (_: Throwable) {
                // Malformed frame — skip and continue. The protocol does not
                // require resync since we already consumed the bytes.
            }
            consumed += frameSize
        }
        // Shift the remaining bytes (a partial frame) to the start.
        if (consumed > 0 && consumed < length) {
            System.arraycopy(buffer, consumed, buffer, 0, length - consumed)
        }
        return length - consumed
    }

    private fun payloadSizeFor(eventType: Int): Int? = when (eventType) {
        0x01 -> 20  // STYLUS_MOVE
        0x02 -> 4   // STYLUS_PROXIMITY
        0x03 -> 4   // STYLUS_BUTTON
        0x04 -> 4   // STYLUS_SCROLL
        0x05 -> 4   // STYLUS_ZOOM
        0x06 -> 4   // CURSOR_DELTA
        0x07 -> 4   // KEY_EVENT
        0x08 -> 4   // CAPTURE_REQUEST
        0x09 -> 4   // CAPTURE_RESPONSE
        else -> null
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 3_000
        private const val HEADER_SIZE = 16
        private const val MAX_FRAME_SIZE = 36 // STYLUS_MOVE
    }
}
