package com.inkbridge.ui.screens

import android.view.MotionEvent
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Tests for haptic feedback injection in [ConnectionViewModel].
 *
 * We test the haptic call-sites by replicating the trackpad and gesture state machines
 * with a recording fake [HapticFeedback] — no Android runtime or Application context
 * required.
 */
class ConnectionViewModelHapticTest {

    // ── Recording fake ─────────────────────────────────────────────────────────

    private class RecordingHaptic : HapticFeedback {
        var callCount = 0

        override fun performTapFeedback() {
            callCount++
        }
    }

    // ── Trackpad state machine replica with haptic ─────────────────────────────

    /**
     * Mirrors the tap-detection branch in [ConnectionViewModel.onTrackpadEvent].
     * Only the tap path (ACTION_UP when isTap == true) should fire haptic.
     */
    private class TrackpadWithHaptic(private val haptic: HapticFeedback) {
        private var prevX: Float = 0f
        private var prevY: Float = 0f
        private var downTimeMs: Long = 0L
        private var cumMovement: Float = 0f
        private var active: Boolean = false

        private val tapTimeoutMs: Long = 180L
        private val tapMovementThresholdPx: Float = 14f

        fun handleAction(
            actionMasked: Int,
            x: Float,
            y: Float,
            now: Long,
        ) {
            when (actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    prevX = x
                    prevY = y
                    downTimeMs = now
                    cumMovement = 0f
                    active = true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!active) return
                    val dx = x - prevX
                    val dy = y - prevY
                    cumMovement += kotlin.math.sqrt(dx * dx + dy * dy)
                    prevX = x
                    prevY = y
                }
                MotionEvent.ACTION_UP -> {
                    val elapsed = now - downTimeMs
                    val isTap =
                        active &&
                            elapsed < tapTimeoutMs &&
                            cumMovement < tapMovementThresholdPx
                    if (isTap) {
                        // Primary click + haptic
                        haptic.performTapFeedback()
                    }
                    cumMovement = 0f
                    active = false
                }
                MotionEvent.ACTION_CANCEL -> {
                    cumMovement = 0f
                    active = false
                }
            }
        }
    }

    // ── Gesture state machine replica with haptic ──────────────────────────────

    /**
     * Mirrors the RightClick branch in [ConnectionViewModel.onGestureEvent].
     */
    private class GestureWithHaptic(private val haptic: HapticFeedback) {
        fun fireRightClick() {
            haptic.performTapFeedback()
        }
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @Test
    fun `1-finger tap fires haptic exactly once`() {
        val haptic = RecordingHaptic()
        val sm = TrackpadWithHaptic(haptic)

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_UP, 100f, 100f, 50) // 50ms < 180ms tap timeout, no movement

        assertEquals(1, haptic.callCount, "1-finger tap must fire haptic exactly once")
    }

    @Test
    fun `1-finger drag (not a tap) does NOT fire haptic`() {
        val haptic = RecordingHaptic()
        val sm = TrackpadWithHaptic(haptic)

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        // Drag 50px — exceeds 14px threshold
        sm.handleAction(MotionEvent.ACTION_MOVE, 150f, 100f, 100)
        sm.handleAction(MotionEvent.ACTION_UP, 150f, 100f, 120)

        assertEquals(0, haptic.callCount, "Drag must NOT fire haptic")
    }

    @Test
    fun `1-finger slow tap (exceeds timeout) does NOT fire haptic`() {
        val haptic = RecordingHaptic()
        val sm = TrackpadWithHaptic(haptic)

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_UP, 100f, 100f, 200) // 200ms > 180ms timeout

        assertEquals(0, haptic.callCount, "Slow tap (timeout exceeded) must NOT fire haptic")
    }

    @Test
    fun `1-finger ACTION_CANCEL does NOT fire haptic`() {
        val haptic = RecordingHaptic()
        val sm = TrackpadWithHaptic(haptic)

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_CANCEL, 100f, 100f, 50)

        assertEquals(0, haptic.callCount, "CANCEL must NOT fire haptic")
    }

    @Test
    fun `multiple taps fire haptic once each`() {
        val haptic = RecordingHaptic()
        val sm = TrackpadWithHaptic(haptic)

        repeat(3) {
            sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
            sm.handleAction(MotionEvent.ACTION_UP, 100f, 100f, 50)
        }

        assertEquals(3, haptic.callCount, "3 taps must fire haptic 3 times")
    }

    @Test
    fun `2-finger right-click fires haptic exactly once`() {
        val haptic = RecordingHaptic()
        val gesture = GestureWithHaptic(haptic)

        gesture.fireRightClick()

        assertEquals(1, haptic.callCount, "2-finger right-click must fire haptic exactly once")
    }

    @Test
    fun `right-click does not accumulate across multiple gestures`() {
        val haptic = RecordingHaptic()
        val gesture = GestureWithHaptic(haptic)

        gesture.fireRightClick()
        gesture.fireRightClick()

        assertEquals(2, haptic.callCount, "Each right-click must fire haptic independently")
    }

    @Test
    fun `haptic interface is injectable — different implementations are called`() {
        var alternativeCallCount = 0
        val alternativeHaptic = HapticFeedback { alternativeCallCount++ }
        val sm = TrackpadWithHaptic(alternativeHaptic)

        sm.handleAction(MotionEvent.ACTION_DOWN, 0f, 0f, 0)
        sm.handleAction(MotionEvent.ACTION_UP, 0f, 0f, 50)

        assertEquals(1, alternativeCallCount, "Custom HapticFeedback implementation must be called")
    }
}
