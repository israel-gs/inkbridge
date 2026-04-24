package com.inkbridge.ui.screens

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.inkbridge.data.capture.AndroidMotionEvent
import com.inkbridge.data.capture.MotionEventMapper
import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind
import com.inkbridge.domain.usecase.StreamStylus
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * ViewModel for [ConnectionScreen] and [StatusScreen].
 *
 * Owns [ConnectionManager] and [StreamStylus]. Wires capture → encoding → transport.
 *
 * Manual DI: instantiated via [Factory] in [MainActivity]. No Hilt in this change.
 *
 * Exposes:
 * - [connectionState] — mirrors [ConnectionManager.state].
 * - [stats] — packet/drop/bytes counters for the status screen.
 * - [onMotion] — called by [CaptureSurface] with each MotionEvent.
 */
class ConnectionViewModel(
    application: Application,
    private val connectionManager: ConnectionManager,
) : AndroidViewModel(application) {

    // Secondary constructor required by `AndroidViewModelFactory`, which uses
    // reflection to find an `(Application)` ctor. Kotlin default values aren't
    // exposed to reflection, so we bridge here.
    @Suppress("unused")
    constructor(application: Application) : this(application, ConnectionManager())

    val connectionState: StateFlow<ConnectionState> = connectionManager.state

    // StreamStylus is recreated on each connect; initially null transport (no-op).
    @Volatile
    private var streamStylus: StreamStylus = StreamStylus(transport = null)

    // ── Stats exposed to UI ────────────────────────────────────────────────────

    val stats: StateFlow<Stats> = connectionManager.state
        .map { state ->
            when (state) {
                is ConnectionState.Connected -> Stats(
                    transportLabel = if (state.kind == TransportKind.WIFI_UDP) "Wi-Fi" else "USB",
                    packetsSent = streamStylus.sentCount.value,
                    dropped = streamStylus.droppedCount.value,
                )
                else -> Stats()
            }
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = Stats(),
        )

    // ── Actions ────────────────────────────────────────────────────────────────

    /**
     * Initiates a connection.
     *
     * [host] is ignored for USB_TCP (pinned to 127.0.0.1 in ConnectionManager).
     */
    fun connect(host: String, port: Int, kind: TransportKind) {
        viewModelScope.launch {
            connectionManager.connect(host, port, kind)
            // Re-wire StreamStylus to the newly created transport
            streamStylus = StreamStylus(transport = connectionManager.currentTransport())
        }
    }

    fun disconnect() {
        viewModelScope.launch {
            connectionManager.disconnect()
            streamStylus = StreamStylus(transport = null)
        }
    }

    /**
     * Called by [CaptureSurface] for every MotionEvent.
     *
     * Ignored when not in [ConnectionState.Connected] state (ui.md R4).
     *
     * @param event  The raw Android MotionEvent.
     * @param viewWidth  Pixel width of the capture surface.
     * @param viewHeight Pixel height of the capture surface.
     */
    fun onMotion(
        event: android.view.MotionEvent,
        viewWidth: Int,
        viewHeight: Int,
    ) {
        if (connectionState.value !is ConnectionState.Connected) return
        val mapped = MotionEventMapper.map(
            AndroidMotionEvent(event, viewWidth, viewHeight),
        )
        viewModelScope.launch {
            for (sample in mapped) {
                streamStylus.emit(sample)
            }
        }
    }

    // ── Stats data class ───────────────────────────────────────────────────────

    data class Stats(
        val transportLabel: String = "",
        val packetsSent: Int = 0,
        val dropped: Int = 0,
    )
}
