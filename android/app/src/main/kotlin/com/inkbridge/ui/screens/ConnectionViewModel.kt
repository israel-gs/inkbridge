package com.inkbridge.ui.screens

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.inkbridge.data.capture.AndroidMotionEvent
import com.inkbridge.data.capture.MotionEventMapper
import com.inkbridge.data.capture.StylusRouter
import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.TransportKind
import com.inkbridge.domain.usecase.StreamStylus
import kotlinx.coroutines.Dispatchers
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
 * ## Hot-path design
 *
 * [onMotion] is called on the Compose pointer-input thread at 100–240 Hz. Routing
 * is delegated to [StylusChannelDispatcher] which uses two channels:
 *
 * - **sampleChannel** — capacity 512, DROP_OLDEST. For MOVE samples.
 * - **priorityChannel** — capacity 64, SUSPEND. For Button and Proximity actions
 *   (must not be dropped).
 *
 * [onMotion] itself is non-suspending and never blocks the pointer callback.
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
     * Called by [CaptureSurface] for every MotionEvent. Non-blocking.
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
        // Samsung S Pen at 240 Hz packs ~10-20 historical samples into each
        // ACTION_MOVE / ACTION_HOVER_MOVE event. Forwarding all of them floods
        // the socket under bursts (900+ sends/sec) and causes intermittent
        // stalls. Drawing apps (Krita, Excalidraw) smooth strokes internally
        // from 60 Hz input fine. Keep only the latest sample for MOVE events;
        // always preserve every sample on transitions (DOWN/UP) where historical
        // data conveys the exact initial/final pressure.
        val effectiveSamples = when (event.actionMasked) {
            android.view.MotionEvent.ACTION_MOVE,
            android.view.MotionEvent.ACTION_HOVER_MOVE,
            -> mapped.lastOrNull()?.let(::listOf).orEmpty()
            else -> mapped
        }
        val actions = StylusRouter.route(
            actionMasked = event.actionMasked,
            samples = effectiveSamples,
            timestampNs = System.nanoTime(),
        )
        // Per-action launch on IO. Prioritises subjective responsiveness — the
        // newest MotionEvent's first sample reaches the transport without
        // waiting for the previous MotionEvent's batch to drain. Samples may
        // arrive out-of-order; the server's sequence-number check drops stale
        // frames per wire-protocol.md R9, so correctness is preserved.
        val sink = streamStylus
        for (action in actions) {
            viewModelScope.launch(Dispatchers.IO) {
                when (action) {
                    is StylusRouter.Action.Sample -> sink.emit(action.sample)
                    is StylusRouter.Action.Button ->
                        sink.emitButton(action.primaryPressed, action.secondaryPressed, action.timestampNs)
                    is StylusRouter.Action.Proximity ->
                        sink.emitProximity(action.entering, action.timestampNs)
                }
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
