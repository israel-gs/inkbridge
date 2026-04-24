package com.inkbridge.data.connection

import com.inkbridge.data.transport.TcpStylusClient
import com.inkbridge.data.transport.UdpStylusClient
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.domain.model.TransportKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Manages transport lifecycle and exposes [ConnectionState] as a [StateFlow].
 *
 * Follows transport.md R6 state machine:
 *   Disconnected → Connecting → Connected(kind)
 *                             ↘ Error(reason)
 *
 * USB_TCP pins host to 127.0.0.1 per transport.md R4. The host parameter is ignored
 * when kind == USB_TCP.
 *
 * No auto-reconnect in this change (transport.md R6).
 *
 * Thread safety: [connect] and [disconnect] are suspending and must be called from
 * a single coroutine (ViewModel scope). The StateFlow is safe for multiple observers.
 */
class ConnectionManager(
    private val transportFactory: TransportFactory = DefaultTransportFactory,
) {

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    @Volatile
    private var activeTransport: StylusTransport? = null

    /**
     * Establishes a connection to [host]:[port] using [kind] transport.
     *
     * USB_TCP ignores [host] and always connects to 127.0.0.1 (transport.md R4).
     */
    suspend fun connect(host: String, port: Int, kind: TransportKind) {
        _state.value = ConnectionState.Connecting

        val effectiveHost = when (kind) {
            TransportKind.USB_TCP -> "127.0.0.1"
            TransportKind.WIFI_UDP -> host
        }

        val transport = transportFactory.create(effectiveHost, port, kind)
        val result = transport.connect()

        if (result.isSuccess) {
            activeTransport = transport
            _state.value = ConnectionState.Connected(kind)
        } else {
            transport.close()
            _state.value = ConnectionState.Error(
                result.exceptionOrNull()?.message ?: "Connection failed",
            )
        }
    }

    /** Returns the active [StylusTransport] or null when not connected. */
    fun currentTransport(): StylusTransport? = activeTransport

    /** Closes the active transport and transitions to [ConnectionState.Disconnected]. */
    suspend fun disconnect() {
        activeTransport?.close()
        activeTransport = null
        _state.value = ConnectionState.Disconnected
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Factory
    // ─────────────────────────────────────────────────────────────────────────

    fun interface TransportFactory {
        fun create(host: String, port: Int, kind: TransportKind): StylusTransport
    }

    object DefaultTransportFactory : TransportFactory {
        override fun create(host: String, port: Int, kind: TransportKind): StylusTransport =
            when (kind) {
                TransportKind.WIFI_UDP -> UdpStylusClient(host, port)
                TransportKind.USB_TCP -> TcpStylusClient(host, port)
            }
    }
}
