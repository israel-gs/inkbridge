package com.inkbridge.data.connection

import com.inkbridge.data.transport.TcpStylusClient
import com.inkbridge.data.transport.UdpStylusClient
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusTransport
import com.inkbridge.domain.model.TransportKind
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

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
 * ## Mid-session disconnect detection (Bug 3 fix)
 *
 * After a successful connect, [ConnectionManager] subscribes to [StylusTransport.errors].
 * The first error transitions state to [ConnectionState.Error] so the UI immediately
 * reflects a broken connection instead of remaining stuck in "Connected".
 *
 * Thread safety: [connect] and [disconnect] are suspending and must be called from
 * a single coroutine (ViewModel scope). The StateFlow is safe for multiple observers.
 */
class ConnectionManager(
    private val transportFactory: TransportFactory = DefaultTransportFactory,
    private val errorScope: CoroutineScope = CoroutineScope(Dispatchers.IO),
) {
    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    @Volatile
    private var activeTransport: StylusTransport? = null

    /** Tracks the coroutine that watches [StylusTransport.errors] for the active transport. */
    private var errorWatchJob: Job? = null

    /**
     * Establishes a connection to [host]:[port] using [kind] transport.
     *
     * USB_TCP ignores [host] and always connects to 127.0.0.1 (transport.md R4).
     */
    suspend fun connect(
        host: String,
        port: Int,
        kind: TransportKind,
    ) {
        _state.value = ConnectionState.Connecting

        val effectiveHost =
            when (kind) {
                TransportKind.USB_TCP -> "127.0.0.1"
                TransportKind.WIFI_UDP -> host
            }

        val transport = transportFactory.create(effectiveHost, port, kind)
        val result = transport.connect()

        if (result.isSuccess) {
            activeTransport = transport
            _state.value = ConnectionState.Connected(kind)
            // Watch for mid-session I/O errors. The first error transitions state to
            // Error so the UI stops showing "Connected" after a cable unplug or server
            // crash. transport.md R4. Cancel any prior watcher from a previous connect.
            errorWatchJob?.cancel()
            errorWatchJob =
                errorScope.launch {
                    transport.errors.collect { cause ->
                        // Only transition if we are still in Connected state — avoid
                        // overwriting an explicit user-initiated Disconnected.
                        if (_state.value is ConnectionState.Connected) {
                            _state.value =
                                ConnectionState.Error(
                                    cause.message ?: "Connection lost",
                                )
                        }
                    }
                }
        } else {
            transport.close()
            _state.value =
                ConnectionState.Error(
                    result.exceptionOrNull()?.message ?: "Connection failed",
                )
        }
    }

    /** Returns the active [StylusTransport] or null when not connected. */
    fun currentTransport(): StylusTransport? = activeTransport

    /** Closes the active transport and transitions to [ConnectionState.Disconnected]. */
    suspend fun disconnect() {
        errorWatchJob?.cancel()
        errorWatchJob = null
        activeTransport?.close()
        activeTransport = null
        _state.value = ConnectionState.Disconnected
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Factory
    // ─────────────────────────────────────────────────────────────────────────

    fun interface TransportFactory {
        fun create(
            host: String,
            port: Int,
            kind: TransportKind,
        ): StylusTransport
    }

    object DefaultTransportFactory : TransportFactory {
        override fun create(
            host: String,
            port: Int,
            kind: TransportKind,
        ): StylusTransport =
            when (kind) {
                TransportKind.WIFI_UDP -> UdpStylusClient(host, port)
                TransportKind.USB_TCP -> TcpStylusClient(host, port)
            }
    }
}
