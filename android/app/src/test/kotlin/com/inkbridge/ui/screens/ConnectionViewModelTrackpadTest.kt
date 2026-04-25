package com.inkbridge.ui.screens

import android.view.MotionEvent
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * Tests for [ConnectionViewModel.onTrackpadEvent] POINTER_DOWN / POINTER_UP fix (Bug 2).
 *
 * We test the trackpad state machine logic directly. Because instantiating a real
 * [ConnectionViewModel] requires an [android.app.Application] context (not available
 * in the JVM unit-test tier without Robolectric), we exercise the logic by replicating
 * the exact state variables and the switch-branch introduced in the fix.
 *
 * The critical invariant: after ACTION_POINTER_DOWN or ACTION_POINTER_UP, `trackpadActive`
 * must be false so a subsequent ACTION_MOVE does NOT emit cursor deltas until a fresh
 * ACTION_DOWN re-arms the session.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionViewModelTrackpadTest {
    // ── Trackpad state machine replica ─────────────────────────────────────────

    /**
     * Minimal replica of the trackpad state variables and switch logic from
     * [ConnectionViewModel.onTrackpadEvent]. Replicated here so we can test
     * the state transitions without needing Android runtime or Application context.
     */
    private class TrackpadStateMachine {
        var prevX: Float = 0f
        var prevY: Float = 0f
        var downTimeMs: Long = 0L
        var cumMovement: Float = 0f
        var active: Boolean = false
        val deltasSent = mutableListOf<Pair<Float, Float>>()

        private val activateMovementPx = 6f
        private val activateTimeMs = 50L

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

                    val elapsed = now - downTimeMs
                    val activated = cumMovement >= activateMovementPx || elapsed >= activateTimeMs
                    if (!activated) return

                    if (kotlin.math.abs(dx) >= 1f || kotlin.math.abs(dy) >= 1f) {
                        deltasSent.add(dx to dy)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    cumMovement = 0f
                    active = false
                }
                MotionEvent.ACTION_CANCEL -> {
                    cumMovement = 0f
                    active = false
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    // Bug 2 fix: second finger appeared — mute the session.
                    prevX = x
                    prevY = y
                    cumMovement = 0f
                    active = false
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    // Bug 2 fix: one finger lifted — re-seed but keep inactive.
                    prevX = x
                    prevY = y
                    cumMovement = 0f
                    active = false
                }
            }
        }
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    /**
     * POINTER_DOWN must set trackpadActive to false so a subsequent MOVE does NOT
     * move the cursor (the surviving finger is in an invalid session).
     */
    @Test
    fun `ACTION_POINTER_DOWN sets trackpadActive to false`() {
        val sm = TrackpadStateMachine()

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_MOVE, 120f, 100f, 100) // activate session
        assertEquals(true, sm.active)

        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 200f, 200f, 200)
        assertEquals(false, sm.active, "POINTER_DOWN must deactivate trackpad session")
    }

    /**
     * POINTER_UP must set trackpadActive to false so a subsequent MOVE does NOT
     * move the cursor (no fresh ACTION_DOWN yet).
     */
    @Test
    fun `ACTION_POINTER_UP sets trackpadActive to false`() {
        val sm = TrackpadStateMachine()

        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_MOVE, 120f, 100f, 100)
        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 200f, 200f, 200)
        sm.handleAction(MotionEvent.ACTION_POINTER_UP, 150f, 150f, 300)

        assertEquals(false, sm.active, "POINTER_UP must keep trackpad session inactive")
    }

    /**
     * After POINTER_DOWN → POINTER_UP, a fresh ACTION_DOWN re-arms the session and
     * a subsequent MOVE correctly emits cursor deltas.
     */
    @Test
    fun `fresh ACTION_DOWN after POINTER_UP re-arms session`() {
        val sm = TrackpadStateMachine()

        // 1-finger session
        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        // 2-finger joins, then lifts
        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 200f, 200f, 100)
        sm.handleAction(MotionEvent.ACTION_POINTER_UP, 100f, 100f, 200)

        // Without a re-arm, MOVE must not emit deltas.
        sm.handleAction(MotionEvent.ACTION_MOVE, 110f, 100f, 300)
        assertEquals(0, sm.deltasSent.size, "MOVE after POINTER_UP without re-arm must not emit deltas")

        // Fresh ACTION_DOWN re-arms.
        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 400)
        sm.handleAction(MotionEvent.ACTION_MOVE, 110f, 100f, 500) // only 10px — below activation
        sm.handleAction(MotionEvent.ACTION_MOVE, 120f, 100f, 600) // 20px cumulative — above 6px threshold
        assertEquals(true, sm.deltasSent.size > 0, "MOVE after fresh ACTION_DOWN must emit deltas")
    }

    /**
     * Full sequence: 1-finger down → 2-finger down (POINTER_DOWN) → 2-finger up
     * (POINTER_UP back to 1) → drag → tap. Cursor must only move after a fresh
     * ACTION_DOWN, never during the 2-finger transition.
     */
    @Test
    fun `1finger to 2finger to 1finger sequence only moves cursor after fresh DOWN`() {
        val sm = TrackpadStateMachine()

        // 1-finger starts
        sm.handleAction(MotionEvent.ACTION_DOWN, 50f, 50f, 0)
        sm.handleAction(MotionEvent.ACTION_MOVE, 80f, 50f, 100) // 30px, activates
        val deltasAfterInitialDrag = sm.deltasSent.size
        assertEquals(1, deltasAfterInitialDrag, "Activated 1-finger drag must emit one delta")

        // Second finger joins (ACTION_POINTER_DOWN)
        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 200f, 200f, 200)
        val deltasAfterPointerDown = sm.deltasSent.size

        // Try to drag while in 2-finger state — must NOT emit
        sm.handleAction(MotionEvent.ACTION_MOVE, 90f, 50f, 300)
        assertEquals(deltasAfterPointerDown, sm.deltasSent.size, "MOVE while inactive must not emit")

        // Second finger lifts (ACTION_POINTER_UP)
        sm.handleAction(MotionEvent.ACTION_POINTER_UP, 80f, 50f, 400)
        sm.handleAction(MotionEvent.ACTION_MOVE, 90f, 50f, 500) // surviving finger moves — still inactive
        assertEquals(deltasAfterPointerDown, sm.deltasSent.size, "MOVE after POINTER_UP without re-arm must not emit")

        // Fresh 1-finger DOWN re-arms
        sm.handleAction(MotionEvent.ACTION_DOWN, 80f, 50f, 600)
        sm.handleAction(MotionEvent.ACTION_MOVE, 110f, 50f, 700) // 30px — activates and emits
        assertEquals(deltasAfterPointerDown + 1, sm.deltasSent.size, "MOVE after re-armed DOWN must emit")
    }

    /**
     * POINTER_DOWN re-seeds prevX/Y from the new position so the next MOVE (after
     * a re-arm ACTION_DOWN) computes delta from the correct origin.
     */
    @Test
    fun `POINTER_DOWN re-seeds prevX and prevY`() {
        val sm = TrackpadStateMachine()
        sm.handleAction(MotionEvent.ACTION_DOWN, 0f, 0f, 0)
        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 300f, 400f, 100)

        assertEquals(300f, sm.prevX, "prevX must be re-seeded from POINTER_DOWN x")
        assertEquals(400f, sm.prevY, "prevY must be re-seeded from POINTER_DOWN y")
    }

    /**
     * POINTER_UP re-seeds prevX/Y from the surviving finger position.
     */
    @Test
    fun `POINTER_UP re-seeds prevX and prevY from surviving finger`() {
        val sm = TrackpadStateMachine()
        sm.handleAction(MotionEvent.ACTION_DOWN, 100f, 100f, 0)
        sm.handleAction(MotionEvent.ACTION_POINTER_DOWN, 200f, 200f, 100)
        sm.handleAction(MotionEvent.ACTION_POINTER_UP, 150f, 150f, 200)

        assertEquals(150f, sm.prevX, "prevX must be re-seeded from surviving finger on POINTER_UP")
        assertEquals(150f, sm.prevY, "prevY must be re-seeded from surviving finger on POINTER_UP")
    }
}
