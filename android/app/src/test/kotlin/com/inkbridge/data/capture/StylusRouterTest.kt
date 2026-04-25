package com.inkbridge.data.capture

import com.inkbridge.data.capture.StylusRouter.Action
import com.inkbridge.data.capture.StylusRouter.Actions
import com.inkbridge.domain.model.StylusSample
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class StylusRouterTest {
    private fun sample(
        x: Float = 0.5f,
        y: Float = 0.5f,
    ) = StylusSample(
        x = x,
        y = y,
        pressure = 32768,
        tiltX = 0,
        tiltY = 0,
        hover = false,
        timestampNs = 0,
    )

    @Test
    fun `ACTION_DOWN emits samples before button press so pressure lands first`() {
        val s = sample()
        val actions = StylusRouter.route(Actions.ACTION_DOWN, listOf(s), timestampNs = 100)
        assertEquals(2, actions.size)
        assertEquals(s, (actions[0] as Action.Sample).sample)
        val btn = actions[1] as Action.Button
        assertTrue(btn.primaryPressed)
        assertTrue(!btn.secondaryPressed)
        assertEquals(100, btn.timestampNs)
    }

    @Test
    fun `ACTION_UP emits samples then button release`() {
        val s = sample()
        val actions = StylusRouter.route(Actions.ACTION_UP, listOf(s), timestampNs = 200)
        assertEquals(2, actions.size)
        assertEquals(s, (actions[0] as Action.Sample).sample)
        val btn = actions[1] as Action.Button
        assertTrue(!btn.primaryPressed)
        assertTrue(!btn.secondaryPressed)
        assertEquals(200, btn.timestampNs)
    }

    @Test
    fun `ACTION_CANCEL behaves like UP — releases primary`() {
        val actions = StylusRouter.route(Actions.ACTION_CANCEL, listOf(sample()), timestampNs = 300)
        val btn = actions.last() as Action.Button
        assertTrue(!btn.primaryPressed)
    }

    @Test
    fun `ACTION_MOVE forwards samples only`() {
        val samples = listOf(sample(0.1f), sample(0.2f), sample(0.3f))
        val actions = StylusRouter.route(Actions.ACTION_MOVE, samples, timestampNs = 0)
        assertEquals(3, actions.size)
        assertTrue(actions.all { it is Action.Sample })
    }

    @Test
    fun `ACTION_HOVER_MOVE forwards samples only`() {
        val actions = StylusRouter.route(Actions.ACTION_HOVER_MOVE, listOf(sample()), timestampNs = 0)
        assertEquals(1, actions.size)
        assertTrue(actions[0] is Action.Sample)
    }

    @Test
    fun `ACTION_HOVER_ENTER emits proximity-enter before samples`() {
        val s = sample()
        val actions = StylusRouter.route(Actions.ACTION_HOVER_ENTER, listOf(s), timestampNs = 400)
        val prox = actions[0] as Action.Proximity
        assertTrue(prox.entering)
        assertEquals(400, prox.timestampNs)
        assertEquals(s, (actions[1] as Action.Sample).sample)
    }

    @Test
    fun `ACTION_HOVER_EXIT emits samples then proximity-exit`() {
        val actions = StylusRouter.route(Actions.ACTION_HOVER_EXIT, listOf(sample()), timestampNs = 500)
        val prox = actions.last() as Action.Proximity
        assertTrue(!prox.entering)
    }

    @Test
    fun `empty samples still emit transition for DOWN`() {
        val actions = StylusRouter.route(Actions.ACTION_DOWN, emptyList(), timestampNs = 0)
        assertEquals(1, actions.size)
        assertTrue(actions[0] is Action.Button)
        assertTrue((actions[0] as Action.Button).primaryPressed)
    }

    @Test
    fun `unknown action still forwards samples`() {
        val actions = StylusRouter.route(actionMasked = 99, samples = listOf(sample()), timestampNs = 0)
        assertEquals(1, actions.size)
    }

    // A6 — ACTION_POINTER_* and ACTION_HOVER_MOVE with samples (falls through to default)

    @Test
    fun `ACTION_POINTER_DOWN with samples falls through to samples-only`() {
        // ACTION_POINTER_DOWN = 5 (MotionEvent constant); not in the StylusRouter explicit when branches.
        // The else branch emits samples.map(Action::Sample) — samples only.
        val actionPointerDown = 5
        val samples = listOf(sample(0.3f), sample(0.4f))
        val actions = StylusRouter.route(actionPointerDown, samples, timestampNs = 0)
        assertEquals(2, actions.size, "ACTION_POINTER_DOWN must produce samples-only (falls to else branch)")
        assertTrue(actions.all { it is Action.Sample }, "All actions must be Action.Sample for POINTER_DOWN")
    }

    @Test
    fun `ACTION_POINTER_UP with samples falls through to samples-only`() {
        // ACTION_POINTER_UP = 6 (MotionEvent constant); handled by else branch → samples only.
        val actionPointerUp = 6
        val samples = listOf(sample())
        val actions = StylusRouter.route(actionPointerUp, samples, timestampNs = 0)
        assertEquals(1, actions.size, "ACTION_POINTER_UP must produce samples-only (falls to else branch)")
        assertTrue(actions[0] is Action.Sample)
    }

    @Test
    fun `ACTION_HOVER_MOVE with multiple samples emits samples-only in order`() {
        // ACTION_HOVER_MOVE = 7; handled explicitly → samples.map(Action::Sample).
        val samples = listOf(sample(0.1f), sample(0.5f), sample(0.9f))
        val actions = StylusRouter.route(StylusRouter.Actions.ACTION_HOVER_MOVE, samples, timestampNs = 0)
        assertEquals(3, actions.size, "ACTION_HOVER_MOVE must produce one Action.Sample per input sample")
        assertTrue(actions.all { it is Action.Sample }, "All must be Action.Sample for HOVER_MOVE")
        // Verify ordering is preserved.
        assertEquals(0.1f, (actions[0] as Action.Sample).sample.x, 1e-5f)
        assertEquals(0.5f, (actions[1] as Action.Sample).sample.x, 1e-5f)
        assertEquals(0.9f, (actions[2] as Action.Sample).sample.x, 1e-5f)
    }
}
