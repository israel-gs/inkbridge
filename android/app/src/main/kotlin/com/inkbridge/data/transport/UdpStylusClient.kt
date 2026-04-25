package com.inkbridge.data.transport

import com.inkbridge.domain.model.StylusTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/**
 * UDP transport — sends each encoded wire frame as a single datagram (transport.md R3).
 *
 * [connect] binds a local socket and sets the remote address. Because UDP is connectionless,
 * [isConnected] becomes true immediately after [connect] succeeds (transport.md R6).
 *
 * All socket operations run on [Dispatchers.IO]. No auto-reconnect (transport.md R6).
 *
 * ## Buffer reuse
 *
 * Under 240 Hz stylus sampling, a new [DatagramPacket] per send produces 240
 * allocations/second and consistent GC pressure. Instead, a single [DatagramPacket]
 * backed by the largest possible frame (40 bytes) is pre-allocated in [connect] and
 * reused across all [send] calls via [DatagramPacket.setData] + [DatagramPacket.setLength].
 *
 * The 40-byte backing array covers the largest InkBridge frame (STYLUS_MOVE: 36 bytes)
 * with a small margin. If a frame ever exceeds this, the packet falls back to a fresh
 * allocation for that call only.
 *
 * @param host Remote host IPv4 or hostname.
 * @param port Remote port [1024, 65535]. Default 4545 (transport.md R1).
 */
class UdpStylusClient(
    private val host: String,
    private val port: Int = 4545,
) : StylusTransport {
    private val _isConnected = MutableStateFlow(false)
    override val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    // UDP is fire-and-forget; send errors don't indicate a broken connection the way
    // TCP does, but we expose the flow to satisfy the StylusTransport contract.
    private val _errors = MutableSharedFlow<Throwable>(extraBufferCapacity = 1)
    override val errors: SharedFlow<Throwable> = _errors.asSharedFlow()

    @Volatile
    private var socket: DatagramSocket? = null

    @Volatile
    private var remoteAddress: InetAddress? = null

    /**
     * Pre-allocated backing buffer for the reusable [DatagramPacket].
     * 40 bytes covers the largest InkBridge frame (STYLUS_MOVE = 36 bytes) with margin.
     */
    private val reuseBuffer = ByteArray(40)

    /**
     * Single reusable [DatagramPacket]. Initialized in [connect]; null before connect.
     *
     * Bug 2 fix: access is serialised by [sendMutex] so that concurrent callers
     * (regardless of dispatcher) cannot race on [reuseBuffer] + [DatagramPacket.setData].
     * The single-threaded channel consumer in ConnectionViewModel provides the primary
     * ordering guarantee; the Mutex is a belt-and-suspenders class-level invariant.
     */
    @Volatile
    private var reusePacket: DatagramPacket? = null

    /** Serialises [send] calls so [reuseBuffer] is never accessed concurrently. */
    private val sendMutex = Mutex()

    override suspend fun connect(): Result<Unit> =
        withContext(Dispatchers.IO) {
            runCatching {
                val addr = InetAddress.getByName(host)
                val sock = DatagramSocket()
                sock.connect(addr, port)
                socket = sock
                remoteAddress = addr
                // Pre-allocate the reusable packet now that the address is known.
                reusePacket = DatagramPacket(reuseBuffer, reuseBuffer.size, addr, port)
                _isConnected.value = true
            }
        }

    override suspend fun send(bytes: ByteArray): Result<Unit> =
        withContext(Dispatchers.IO) {
            sendMutex.withLock {
                runCatching {
                    val sock = socket ?: error("Not connected")
                    val packet = reusePacket
                    if (packet != null && bytes.size <= reuseBuffer.size) {
                        // Fast path: copy into the backing buffer and update length — no allocation.
                        bytes.copyInto(reuseBuffer)
                        packet.setData(reuseBuffer, 0, bytes.size)
                        sock.send(packet)
                    } else {
                        // Slow path: frame larger than the pre-allocated buffer (should not happen
                        // with the current protocol, but safe to handle).
                        sock.send(DatagramPacket(bytes, bytes.size))
                    }
                }
            }
        }

    override suspend fun close() =
        withContext(Dispatchers.IO) {
            _isConnected.value = false
            socket?.close()
            socket = null
            reusePacket = null
        }
}
