package com.inkbridge.ui.screens

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.inkbridge.data.capture.AndroidMotionEvent
import com.inkbridge.data.capture.GestureEvent
import com.inkbridge.data.capture.MotionEventMapper
import com.inkbridge.data.capture.Offset
import com.inkbridge.data.capture.StylusRouter
import com.inkbridge.data.capture.TwoFingerGestureDetector
import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.data.settings.SettingsRepository
import com.inkbridge.domain.model.ConnectionState
import com.inkbridge.domain.model.StylusSink
import com.inkbridge.domain.model.TransportKind
import com.inkbridge.domain.usecase.StreamStylus
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.util.concurrent.Executors
import kotlin.coroutines.CoroutineContext

/**
 * ViewModel for [ConnectionScreen] and [StatusScreen].
 *
 * Owns [ConnectionManager] and [StreamStylus]. Wires capture → encoding → transport.
 *
 * Manual DI: instantiated via [Factory] in [MainActivity]. No Hilt in this change.
 *
 * ## Hot-path design (Bug 1 fix)
 *
 * [onMotion] is called on the Compose pointer-input thread at 100–240 Hz.
 *
 * All emit calls are dispatched through a [Channel] consumed by a **single-threaded**
 * coroutine. This guarantees:
 * - FIFO ordering across all actions from a single MotionEvent (Sample before Button).
 * - One writer to the socket at a time — no concurrent send races (also fixes Bug 2).
 * - Non-blocking caller: [Channel.trySend] never suspends the pointer callback.
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
    emitDispatcher: CoroutineContext? = null,
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

    // ── Single-threaded emit infrastructure (Bug 1 fix) ────────────────────────

    /**
     * Dedicated single-thread executor for all socket writes.
     * A single thread guarantees FIFO ordering and eliminates concurrent-write races.
     * Created here and closed in [onCleared] to avoid leaking the thread.
     */
    private val emitExecutor =
        Executors.newSingleThreadExecutor { r ->
            Thread(r, "inkbridge-emit").also { it.isDaemon = true }
        }
    private val resolvedEmitDispatcher: CoroutineContext =
        emitDispatcher ?: emitExecutor.asCoroutineDispatcher()

    /**
     * Unbounded channel — producer (pointer callback) never blocks. The single
     * consumer drains sequentially so order is always preserved.
     */
    @Suppress("MemberVisibilityCanBePrivate") // testable
    internal val emitChannel = Channel<suspend (StylusSink) -> Unit>(Channel.UNLIMITED)

    // ── StreamStylus singleton (Bug 3/4 fix) ──────────────────────────────────

    /**
     * Single [StreamStylus] instance that lives for the ViewModel's lifetime.
     * On connect/disconnect we call [StreamStylus.swapTransport] rather than
     * replacing the whole object, so counters accumulate across reconnections and
     * in-flight channel jobs always reach the correct transport.
     */
    @Suppress("MemberVisibilityCanBePrivate")
    internal val streamStylus: StreamStylus = StreamStylus(transport = null)

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

    /**
     * Whether the immediately preceding stylus action was ACTION_DOWN.
     * Used to preserve historical samples on the first ACTION_MOVE after a DOWN
     * (Bug A-B6): those historical samples span the DOWN→MOVE gap and carry the
     * initial pressure ramp data.
     */
    @Volatile private var lastActionWasDown: Boolean = false

    // ── Stats exposed to UI ────────────────────────────────────────────────────

    val stats: StateFlow<Stats> =
        connectionManager.state
            .map { state ->
                when (state) {
                    is ConnectionState.Connected ->
                        Stats(
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

    init {
        // Single consumer: drains emitChannel on a dedicated single-thread dispatcher.
        // FIFO is guaranteed because the channel is UNLIMITED (no reordering) and
        // the consumer is sequential (one coroutine, single thread).
        viewModelScope.launch(resolvedEmitDispatcher) {
            for (job in emitChannel) {
                job(streamStylus)
            }
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    /**
     * Initiates a connection.
     *
     * [host] is ignored for USB_TCP (pinned to 127.0.0.1 in ConnectionManager).
     *
     * Bug 4 fix: transport is swapped BEFORE state transitions to Connected so that
     * the very first frames emitted after the state change reach a live socket.
     */
    fun connect(
        host: String,
        port: Int,
        kind: TransportKind,
    ) {
        viewModelScope.launch {
            connectionManager.connect(host, port, kind)
            // swapTransport after connect() so the new transport is ready before
            // any caller observing connectionState.Connected fires onMotion.
            streamStylus.swapTransport(connectionManager.currentTransport())
        }
    }

    fun disconnect() {
        viewModelScope.launch {
            // Null the transport first so in-flight channel jobs see no transport
            // and drop gracefully, rather than writing to a closing socket.
            streamStylus.swapTransport(null)
            connectionManager.disconnect()
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
        val mapped =
            MotionEventMapper.map(
                AndroidMotionEvent(event, viewWidth, viewHeight),
            )
        // Bug A-B6 fix: on the first MOVE after a DOWN, historical samples span the
        // DOWN→MOVE gap and carry the initial pressure ramp. Preserve all of them so
        // drawing apps receive the full ramp instead of starting at zero pressure.
        // For all other MOVE events, keep only the latest sample to avoid flooding
        // the socket at 900+ sends/sec (Samsung S Pen at 240 Hz with ~10-20 historicals).
        val prevWasDown = lastActionWasDown
        lastActionWasDown = (event.actionMasked == android.view.MotionEvent.ACTION_DOWN)

        val effectiveSamples =
            when (event.actionMasked) {
                android.view.MotionEvent.ACTION_MOVE,
                android.view.MotionEvent.ACTION_HOVER_MOVE,
                ->
                    if (prevWasDown) {
                        // First MOVE after DOWN: preserve ALL historicals (Bug A-B6 fix).
                        mapped
                    } else {
                        // Subsequent MOVEs: latest sample only (avoids socket flooding).
                        mapped.lastOrNull()?.let(::listOf).orEmpty()
                    }
                else -> mapped
            }
        val actions =
            StylusRouter.route(
                actionMasked = event.actionMasked,
                samples = effectiveSamples,
                timestampNs = System.nanoTime(),
            )
        // Bug 1 fix: enqueue all actions atomically into the channel.
        // The single-threaded consumer guarantees Sample is delivered before
        // Button for ACTION_DOWN without any per-action launch overhead.
        for (action in actions) {
            emitChannel.trySend(
                when (action) {
                    is StylusRouter.Action.Sample -> { sink -> sink.emit(action.sample) }
                    is StylusRouter.Action.Button -> { sink ->
                        sink.emitButton(action.primaryPressed, action.secondaryPressed, action.timestampNs)
                    }
                    is StylusRouter.Action.Proximity -> { sink ->
                        sink.emitProximity(action.entering, action.timestampNs)
                    }
                },
            )
        }
    }

    /**
     * Called by [CaptureSurface] for every two-finger gesture MotionEvent. Non-blocking.
     *
     * Feeds [TwoFingerGestureDetector] and dispatches [GestureEvent]s through the
     * single-threaded channel used by [onMotion].
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

        val eventTimeMs = event.eventTime

        val gestureEvents: List<GestureEvent> =
            when (event.actionMasked) {
                android.view.MotionEvent.ACTION_POINTER_DOWN,
                android.view.MotionEvent.ACTION_DOWN,
                -> {
                    val spread = kotlin.math.sqrt(dx * dx + dy * dy)
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
                    val tsNow = System.nanoTime()
                    emitChannel.trySend { sink ->
                        sink.emitScroll(deltaX = 0, deltaY = 0, phaseFlags = 0x40u, timestampNs = tsNow)
                    }
                    gestureScrollOpen = true
                    gestureFirstScroll = false
                    emptyList()
                }
                android.view.MotionEvent.ACTION_MOVE -> {
                    val spread = kotlin.math.sqrt(dx * dx + dy * dy)
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

        val naturalScroll = settings.naturalScroll
        val timestampNs = System.nanoTime()

        // If the gesture is ending and a scroll session is open, send a final
        // SCROLL_END frame so the macOS side can transition to momentum phase.
        val isLift =
            event.actionMasked == android.view.MotionEvent.ACTION_POINTER_UP ||
                event.actionMasked == android.view.MotionEvent.ACTION_UP ||
                event.actionMasked == android.view.MotionEvent.ACTION_CANCEL
        if (isLift && gestureScrollOpen) {
            val finalDx = lastScrollDeltaX
            val finalDy = lastScrollDeltaY
            emitChannel.trySend { sink ->
                sink.emitScroll(deltaX = finalDx, deltaY = finalDy, phaseFlags = 0x80u, timestampNs = timestampNs)
            }
            gestureScrollOpen = false
        }

        for (ge in gestureEvents) {
            when (ge) {
                is GestureEvent.Scroll -> {
                    val effectiveDx = if (naturalScroll) ge.deltaX else (-ge.deltaX).toShort()
                    val effectiveDy = if (naturalScroll) ge.deltaY else (-ge.deltaY).toShort()
                    val phase: UByte =
                        if (gestureFirstScroll) {
                            gestureFirstScroll = false
                            gestureScrollOpen = true
                            0x40u
                        } else {
                            0x00u
                        }
                    lastScrollDeltaX = effectiveDx
                    lastScrollDeltaY = effectiveDy
                    emitChannel.trySend { sink ->
                        sink.emitScroll(
                            deltaX = effectiveDx,
                            deltaY = effectiveDy,
                            phaseFlags = phase,
                            timestampNs = timestampNs,
                        )
                    }
                }
                is GestureEvent.Zoom -> {
                    val scaleDelta = ge.scaleDelta
                    emitChannel.trySend { sink ->
                        sink.emitZoom(scaleDelta = scaleDelta, timestampNs = timestampNs)
                    }
                }
                is GestureEvent.RightClick -> {
                    emitChannel.trySend { sink ->
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
                val activated =
                    trackpadCumMovement >= trackpadActivateMovementPx ||
                        elapsed >= trackpadActivateTimeMs
                if (!activated) return

                if (kotlin.math.abs(dx) >= 1f || kotlin.math.abs(dy) >= 1f) {
                    val clampedDx = dx.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
                    val clampedDy = dy.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
                    emitChannel.trySend { sink ->
                        sink.emitCursorDelta(deltaX = clampedDx, deltaY = clampedDy, timestampNs = timestampNs)
                    }
                }
            }
            android.view.MotionEvent.ACTION_UP -> {
                val elapsed = now - trackpadDownTimeMs
                val isTap =
                    trackpadActive &&
                        elapsed < trackpadTapTimeoutMs &&
                        trackpadCumMovement < trackpadTapMovementThresholdPx
                if (isTap) {
                    emitChannel.trySend { sink ->
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
            android.view.MotionEvent.ACTION_POINTER_DOWN -> {
                // A second finger appeared. The ongoing 1-finger session is no longer
                // valid. Re-seed prevX/Y from finger 0 in case it keeps moving, but
                // keep trackpadActive = false so ACTION_MOVE is suppressed until a
                // fresh 1-finger ACTION_DOWN re-arms the session.
                trackpadPrevX = event.getX(0)
                trackpadPrevY = event.getY(0)
                trackpadCumMovement = 0f
                trackpadActive = false
            }
            android.view.MotionEvent.ACTION_POINTER_UP -> {
                // One finger lifted; the surviving finger becomes the new dominant.
                // Re-seed its position so the next MOVE doesn't produce a stale delta,
                // but keep trackpadActive = false until a fresh ACTION_DOWN re-arms.
                trackpadPrevX = event.getX(0)
                trackpadPrevY = event.getY(0)
                trackpadCumMovement = 0f
                trackpadActive = false
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Close the channel first so the consumer coroutine's `for job in emitChannel`
        // loop terminates naturally when it drains the remaining items.
        emitChannel.close()
        // Shut down the single-thread executor so the dedicated thread exits.
        // This is best-effort: the executor will finish any already-running job first.
        emitExecutor.shutdown()
        // Disconnect the transport. viewModelScope is already cancelled here, so we
        // cannot use it — runBlocking is correct: we must not leave an open socket.
        runBlocking { connectionManager.disconnect() }
    }

    // ── Stats data class ───────────────────────────────────────────────────────

    data class Stats(
        val transportLabel: String = "",
        val packetsSent: Int = 0,
        val dropped: Int = 0,
    )
}
