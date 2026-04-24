package com.inkbridge.data.transport

import com.inkbridge.domain.model.StylusTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
 * @param host Remote host IPv4 or hostname.
 * @param port Remote port [1024, 65535]. Default 4545 (transport.md R1).
 */
class UdpStylusClient(
    private val host: String,
    private val port: Int = 4545,
) : StylusTransport {

    private val _isConnected = MutableStateFlow(false)
    override val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    @Volatile
    private var socket: DatagramSocket? = null

    @Volatile
    private var remoteAddress: InetAddress? = null

    override suspend fun connect(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val addr = InetAddress.getByName(host)
            val sock = DatagramSocket()
            sock.connect(addr, port)
            socket = sock
            remoteAddress = addr
            _isConnected.value = true
        }
    }

    override suspend fun send(bytes: ByteArray): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val sock = socket ?: error("Not connected")
            val packet = DatagramPacket(bytes, bytes.size)
            sock.send(packet)
        }
    }

    override suspend fun close() = withContext(Dispatchers.IO) {
        _isConnected.value = false
        socket?.close()
        socket = null
    }
}
