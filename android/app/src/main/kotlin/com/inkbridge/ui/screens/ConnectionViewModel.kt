package com.inkbridge.ui.screens

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.inkbridge.data.capture.AndroidMotionEvent
import com.inkbridge.data.capture.GestureEvent
import com.inkbridge.data.capture.Offset
import com.inkbridge.data.capture.MotionEventMapper
import com.inkbridge.data.capture.StylusRouter
import com.inkbridge.data.capture.TwoFingerGestureDetector
import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.data.settings.SettingsRepository
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusSample
import com.inkbridge.domain.model.TransportKind
import com.inkbridge.domain.usecase.StreamStylus
import kotlin.math.sqrt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
    private val settings: SettingsRepository,
) : AndroidViewModel(application) {

    // Secondary constructor required by `AndroidViewModelFactory`, which uses
    // reflection to find an `(Application)` ctor. Kotlin default values aren't
    // exposed to reflection, so we bridge here.
    @Suppress("unused")
    constructor(application: Application) : this(
        application,
        ConnectionManager(),
        SettingsRepository(
            application.getSharedPreferences("inkbridge_settings", Context.MODE_PRIVATE),
        ),
    )

    val connectionState: StateFlow<ConnectionState> = connectionManager.state

    // ── Settings ───────────────────────────────────────────────────────────────

    private val _naturalScroll = MutableStateFlow(settings.naturalScroll)

    /** Observable natural-scroll setting. True = fingers-direction scrolling (macOS default). */
    val naturalScroll: StateFlow<Boolean> = _naturalScroll.asStateFlow()

    /** Persists the natural-scroll preference and propagates to [naturalScroll]. */
    fun setNaturalScroll(enabled: Boolean) {
        settings.naturalScroll = enabled
        _naturalScroll.value = enabled
    }

    // StreamStylus is recreated on each connect; initially null transport (no-op).
    @Volatile
    private var streamStylus: StreamStylus = StreamStylus(transport = null)

    // Two-finger gesture detector — shared across gesture events.
    private val gestureDetector = TwoFingerGestureDetector()

    /** True until the first scroll of a gesture has fired (used to mark BEGIN). */
    @Volatile private var gestureFirstScroll: Boolean = true
    /** Whether we have already begun a scroll session that needs an END. */
    @Volatile private var gestureScrollOpen: Boolean = false
    /** Last scroll delta — sent again on END so momentum can carry direction. */
    @Volatile private var lastScrollDeltaX: Short = 0
    @Volatile private var lastScrollDeltaY: Short = 0

    // Single-finger trackpad-mode tracking — relative cursor moves + tap → click.
    @Volatile private var trackpadPrevX: Float = 0f
    @Volatile private var trackpadPrevY: Float = 0f
    @Volatile private var trackpadDownTimeMs: Long = 0L
    @Volatile private var trackpadCumMovement: Float = 0f
    /**
     * True only between a fresh ACTION_DOWN and its matching ACTION_UP/CANCEL.
     * Cleared whenever a 2-finger gesture is engaged so that when one of the
     * two fingers lifts (transient pointerCount=1 frames during a gesture),
     * the trackpad path stays muted instead of moving the cursor with the
     * leftover finger's drift.
     */
    @Volatile private var trackpadActive: Boolean = false
    private val trackpadTapTimeoutMs: Long = 180L
    private val trackpadTapMovementThresholdPx: Float = 14f
    /**
     * Guard window at the start of a fresh 1-finger session: suppress cursor
     * deltas until the user clearly intends to drive the trackpad (movement
     * threshold OR time elapsed). Filters tiny twitches before a 2-finger
     * gesture is recognised.
     */
    private val trackpadActivateMovementPx: Float = 6f
    private val trackpadActivateTimeMs: Long = 50L

    // Last known stylus position in normalised [0,1] coordinates.
    // Used to position the cursor before emitting a right-click button event.
    @Volatile
    private var lastNormX: Float = 0.5f
    @Volatile
    private var lastNormY: Float = 0.5f

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

    /**
     * Called by [CaptureSurface] for every two-finger gesture MotionEvent. Non-blocking.
     *
     * Feeds [TwoFingerGestureDetector] and dispatches [GestureEvent]s through the
     * same fire-and-forget IO coroutine pattern used by [onMotion].
     *
     * Natural-scroll inversion is applied here before transmission so the wire
     * format carries the canonical direction and the macOS side need not know about
     * the Android preference.
     *
     * @param event      The raw Android MotionEvent (2-finger only).
     * @param viewWidth  Pixel width of the capture surface.
     * @param viewHeight Pixel height of the capture surface.
     */
    fun onGestureEvent(
        event: android.view.MotionEvent,
        viewWidth: Int,
        viewHeight: Int,
    ) {
        if (connectionState.value !is ConnectionState.Connected) return
        // Mute the trackpad path. When one of the two fingers lifts mid-gesture,
        // the resulting solo-finger MOVE frames must NOT move the cursor.
        trackpadActive = false

        val cx = (event.getX(0) + event.getX(1)) / 2f
        val cy = (event.getY(0) + event.getY(1)) / 2f
        val centroid = Offset(cx, cy)

        val dx = event.getX(1) - event.getX(0)
        val dy = event.getY(1) - event.getY(0)
        val spread = kotlin.math.sqrt(dx * dx + dy * dy)

        val eventTimeMs = event.eventTime

        val gestureEvents: List<GestureEvent> = when (event.actionMasked) {
            android.view.MotionEvent.ACTION_POINTER_DOWN,
            android.view.MotionEvent.ACTION_DOWN,
            -> {
                gestureDetector.onTwoFingersDown(centroid, spread, eventTimeMs, viewWidth, viewHeight)
                gestureFirstScroll = true
                // Reset the lift-velocity seed so a touch-down → lift without any
                // movement can't relaunch momentum using the prior gesture's delta.
                lastScrollDeltaX = 0
                lastScrollDeltaY = 0
                // Send a synthetic SCROLL_BEGIN with delta=0 so the macOS side
                // cancels any in-flight momentum from a previous gesture as soon
                // as the user lays fingers back on the surface (Magic Trackpad
                // behaviour) — without waiting for the first real scroll move.
                val sinkSnap = streamStylus
                val tsNow = System.nanoTime()
                viewModelScope.launch(Dispatchers.IO) {
                    sinkSnap.emitScroll(deltaX = 0, deltaY = 0, phaseFlags = 0x40u, timestampNs = tsNow)
                }
                gestureScrollOpen = true
                gestureFirstScroll = false
                emptyList()
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                gestureDetector.onTwoFingersMove(centroid, spread, eventTimeMs)
            }
            android.view.MotionEvent.ACTION_POINTER_UP,
            android.view.MotionEvent.ACTION_UP,
            android.view.MotionEvent.ACTION_CANCEL,
            -> {
                gestureDetector.onTwoFingersUp(eventTimeMs)
            }
            else -> emptyList()
        }

        val sink = streamStylus
        val naturalScroll = settings.naturalScroll
        val timestampNs = System.nanoTime()

        // If the gesture is ending and a scroll session is open, send a final
        // SCROLL_END frame so the macOS side can transition to momentum phase.
        // lastScrollDelta* already holds the natural-scroll-corrected values
        // emitted on the wire — re-inverting here would flip the momentum.
        val isLift = event.actionMasked == android.view.MotionEvent.ACTION_POINTER_UP ||
            event.actionMasked == android.view.MotionEvent.ACTION_UP ||
            event.actionMasked == android.view.MotionEvent.ACTION_CANCEL
        if (isLift && gestureScrollOpen) {
            val finalDx = lastScrollDeltaX
            val finalDy = lastScrollDeltaY
            viewModelScope.launch(Dispatchers.IO) {
                sink.emitScroll(deltaX = finalDx, deltaY = finalDy, phaseFlags = 0x80u, timestampNs = timestampNs)
            }
            gestureScrollOpen = false
        }

        for (ge in gestureEvents) {
            viewModelScope.launch(Dispatchers.IO) {
                when (ge) {
                    is GestureEvent.Scroll -> {
                        val effectiveDx = if (naturalScroll) ge.deltaX else (-ge.deltaX).toShort()
                        val effectiveDy = if (naturalScroll) ge.deltaY else (-ge.deltaY).toShort()
                        // Tag first scroll of a gesture with BEGIN so macOS
                        // transitions kCGScrollPhase from null → began. Subsequent
                        // events use 0 (changed). On lift the loop below sends END.
                        val phase: UByte = if (gestureFirstScroll) {
                            gestureFirstScroll = false
                            gestureScrollOpen = true
                            0x40u
                        } else {
                            0x00u
                        }
                        lastScrollDeltaX = effectiveDx
                        lastScrollDeltaY = effectiveDy
                        sink.emitScroll(deltaX = effectiveDx, deltaY = effectiveDy, phaseFlags = phase, timestampNs = timestampNs)
                    }
                    is GestureEvent.Zoom -> {
                        sink.emitZoom(scaleDelta = ge.scaleDelta, timestampNs = timestampNs)
                    }
                    is GestureEvent.RightClick -> {
                        // Trackpad behaviour: right-click fires at the CURRENT cursor
                        // position, not where the fingers tapped. The Mac server's
                        // lastPoint is kept in sync by the cursorDelta path, so we
                        // simply emit the secondary button down + up. Sending a MOVE
                        // here would teleport the cursor to the tap centroid.
                        sink.emitButton(primaryPressed = false, secondaryPressed = true, timestampNs = timestampNs)
                        sink.emitButton(primaryPressed = false, secondaryPressed = false, timestampNs = timestampNs)
                    }
                }
            }
        }
    }

    /**
     * Called by [CaptureSurface] for every single-finger MotionEvent (trackpad mode).
     * Translates finger movement into relative cursor deltas and quick taps into
     * primary mouse clicks.
     */
    fun onTrackpadEvent(
        event: android.view.MotionEvent,
        viewWidth: Int,
        viewHeight: Int,
    ) {
        if (connectionState.value !is ConnectionState.Connected) return

        val x = event.getX(0)
        val y = event.getY(0)
        val now = event.eventTime
        val sink = streamStylus
        val timestampNs = System.nanoTime()

        when (event.actionMasked) {
            android.view.MotionEvent.ACTION_DOWN -> {
                trackpadPrevX = x
                trackpadPrevY = y
                trackpadDownTimeMs = now
                trackpadCumMovement = 0f
                trackpadActive = true
            }
            android.view.MotionEvent.ACTION_MOVE -> {
                // If we transitioned here from a 2-finger gesture (e.g. one
                // finger lifted while the other still drags), the session is
                // stale — don't move the cursor.
                if (!trackpadActive) return

                val dx = x - trackpadPrevX
                val dy = y - trackpadPrevY
                trackpadCumMovement += kotlin.math.sqrt(dx * dx + dy * dy)
                trackpadPrevX = x
                trackpadPrevY = y

                // Activation guard at session start.
                val elapsed = now - trackpadDownTimeMs
                val activated = trackpadCumMovement >= trackpadActivateMovementPx ||
                    elapsed >= trackpadActivateTimeMs
                if (!activated) return

                if (kotlin.math.abs(dx) >= 1f || kotlin.math.abs(dy) >= 1f) {
                    val clampedDx = dx.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
                    val clampedDy = dy.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
                    viewModelScope.launch(Dispatchers.IO) {
                        sink.emitCursorDelta(deltaX = clampedDx, deltaY = clampedDy, timestampNs = timestampNs)
                    }
                }
            }
            android.view.MotionEvent.ACTION_UP -> {
                val elapsed = now - trackpadDownTimeMs
                val isTap = trackpadActive &&
                    elapsed < trackpadTapTimeoutMs &&
                    trackpadCumMovement < trackpadTapMovementThresholdPx
                if (isTap) {
                    viewModelScope.launch(Dispatchers.IO) {
                        sink.emitButton(primaryPressed = true, secondaryPressed = false, timestampNs = timestampNs)
                        sink.emitButton(primaryPressed = false, secondaryPressed = false, timestampNs = timestampNs)
                    }
                }
                trackpadCumMovement = 0f
                trackpadActive = false
            }
            android.view.MotionEvent.ACTION_CANCEL -> {
                trackpadCumMovement = 0f
                trackpadActive = false
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
