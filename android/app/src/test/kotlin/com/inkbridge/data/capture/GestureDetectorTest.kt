package com.inkbridge.data.capture

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Unit tests for [TwoFingerGestureDetector].
 *
 * All tests use pure-Kotlin [Offset] — no Android runtime required.
 */
class GestureDetectorTest {
    private lateinit var detector: TwoFingerGestureDetector

    @BeforeEach
    fun setUp() {
        detector =
            TwoFingerGestureDetector(
                tapMovementThresholdPx = 12f,
                tapTimeoutMs = 150L,
            )
    }

    // ─────────────────────────────────────────────────────────────
    // Scroll — centroid moves, spread constant
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `pure scroll emits Scroll only when centroid moves`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Move centroid down 30px; spread unchanged.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(100f, 130f),
                spread = 200f,
                eventTimeMs = 50L,
            )

        assertEquals(1, events.size)
        val scroll = assertInstanceOf(GestureEvent.Scroll::class.java, events[0])
        assertEquals(0.toShort(), scroll.deltaX)
        assertEquals(30.toShort(), scroll.deltaY)
    }

    @Test
    fun `scroll below threshold emits nothing`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Move only 1px — below the 1.5px threshold.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(100f, 101f),
                spread = 200f,
                eventTimeMs = 10L,
            )

        assertTrue(events.isEmpty())
    }

    // ─────────────────────────────────────────────────────────────
    // Zoom — spread changes, centroid stable
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `pure pinch emits Zoom only when spread changes`() {
        detector.onTwoFingersDown(
            centroid = Offset(500f, 500f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Spread increases to 240 (20% zoom in); centroid unchanged.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(500f, 500f),
                spread = 240f,
                eventTimeMs = 50L,
            )

        assertEquals(1, events.size)
        val zoom = assertInstanceOf(GestureEvent.Zoom::class.java, events[0])
        assertEquals(1.2f, zoom.scaleDelta, 1e-5f)
    }

    @Test
    fun `zoom below threshold emits nothing`() {
        detector.onTwoFingersDown(
            centroid = Offset(500f, 500f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Spread changes by 0.5% — below 0.5% threshold.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(500f, 500f),
                spread = 201f,
                eventTimeMs = 10L,
            )

        // 201/200 = 1.005 → abs(1.005 - 1.0) = 0.005 → exactly at boundary.
        // Boundary is > 0.005, so 0.005 is NOT emitted.
        assertTrue(events.none { it is GestureEvent.Zoom })
    }

    // ─────────────────────────────────────────────────────────────
    // Combined — scroll and zoom in the same move frame
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `combined scroll and zoom both emitted on same move`() {
        detector.onTwoFingersDown(
            centroid = Offset(500f, 500f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Centroid moves 20px and spread grows 20%.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(500f, 520f),
                spread = 240f,
                eventTimeMs = 50L,
            )

        assertEquals(2, events.size)
        assertTrue(events.any { it is GestureEvent.Scroll })
        assertTrue(events.any { it is GestureEvent.Zoom })
    }

    // ─────────────────────────────────────────────────────────────
    // Right-click (tap)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `quick tap with minimal movement emits RightClick at centroid`() {
        detector.onTwoFingersDown(
            centroid = Offset(540f, 960f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Small move (1px) — stays within tap movement threshold.
        detector.onTwoFingersMove(
            centroid = Offset(540f, 961f),
            spread = 100f,
            eventTimeMs = 30L,
        )

        val events = detector.onTwoFingersUp(eventTimeMs = 80L)

        assertEquals(1, events.size)
        val click = assertInstanceOf(GestureEvent.RightClick::class.java, events[0])
        // Centroid at finger-down: (540/1080, 960/1920) = (0.5, 0.5)
        assertEquals(0.5f, click.xNormalized, 1e-5f)
        assertEquals(0.5f, click.yNormalized, 1e-5f)
    }

    @Test
    fun `tap disqualified when movement exceeds threshold`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Move 20px — exceeds 12px tap threshold.
        detector.onTwoFingersMove(
            centroid = Offset(100f, 120f),
            spread = 100f,
            eventTimeMs = 50L,
        )

        val events = detector.onTwoFingersUp(eventTimeMs = 80L)
        assertTrue(events.isEmpty())
    }

    @Test
    fun `tap held too long does not emit RightClick`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Up after 200ms (> 150ms timeout).
        val events = detector.onTwoFingersUp(eventTimeMs = 200L)
        assertTrue(events.isEmpty())
    }

    @Test
    fun `multiple move frames do not double-fire RightClick on up`() {
        detector.onTwoFingersDown(
            centroid = Offset(540f, 960f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        // Several tiny moves — still within tap threshold cumulatively.
        repeat(3) { i ->
            detector.onTwoFingersMove(
                centroid = Offset(540f + i * 0.5f, 960f),
                spread = 100f,
                eventTimeMs = (i * 10).toLong(),
            )
        }

        val events = detector.onTwoFingersUp(eventTimeMs = 50L)
        assertEquals(1, events.size)
        assertInstanceOf(GestureEvent.RightClick::class.java, events[0])
    }

    @Test
    fun `reset clears in-progress state so subsequent gesture starts fresh`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        detector.reset()

        // After reset, up should produce nothing (no downCentroid recorded).
        val events = detector.onTwoFingersUp(eventTimeMs = 50L)
        assertTrue(events.isEmpty())
    }

    // ─────────────────────────────────────────────────────────────
    // Edge cases
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `move before down does not crash and emits nothing`() {
        // No prior onTwoFingersDown call.
        val events =
            detector.onTwoFingersMove(
                centroid = Offset(100f, 100f),
                spread = 100f,
                eventTimeMs = 0L,
            )
        assertTrue(events.isEmpty())
    }

    // A8 — Boundary conditions

    @Test
    fun `tap at exactly 150ms is NOT a tap (timeout is exclusive)`() {
        // tapTimeoutMs=150, elapsed must be STRICTLY < 150 to qualify.
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )
        // Up at exactly 150ms — condition is `elapsed < tapTimeoutMs`, so 150 is not a tap.
        val events = detector.onTwoFingersUp(eventTimeMs = 150L)
        assertTrue(
            events.isEmpty(),
            "Tap at exactly tapTimeoutMs (150ms) must NOT qualify (elapsed < timeout is strict)",
        )
    }

    @Test
    fun `tap at 149ms with zero movement IS a tap`() {
        detector.onTwoFingersDown(
            centroid = Offset(200f, 300f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )
        // Up at 149ms — just within the 150ms timeout.
        val events = detector.onTwoFingersUp(eventTimeMs = 149L)
        assertEquals(1, events.size, "Tap at 149ms with no movement must qualify as RightClick")
        assertInstanceOf(GestureEvent.RightClick::class.java, events[0])
    }

    @Test
    fun `movement of 11dot5px is under 12px threshold — tap qualifies`() {
        // tapMovementThresholdPx=12; cumulative movement of 11.5 is below threshold.
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 100f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )
        // Move 11.5px — strictly below 12px → tap not disqualified.
        detector.onTwoFingersMove(
            centroid = Offset(100f + 11.5f, 100f),
            spread = 100f,
            eventTimeMs = 50L,
        )
        val events = detector.onTwoFingersUp(eventTimeMs = 80L)
        assertEquals(1, events.size, "Movement of 11.5px is below 12px threshold — tap must qualify")
        assertInstanceOf(GestureEvent.RightClick::class.java, events[0])
    }

    @Test
    fun `three rapid taps in succession each qualify independently after reset`() {
        // Each tap uses a fresh detector or calls reset() between gestures.
        // Simulate via onTwoFingersDown→Up three times with reset between.
        repeat(3) { i ->
            detector.onTwoFingersDown(
                centroid = Offset(540f, 960f),
                spread = 100f,
                eventTimeMs = (i * 300).toLong(),
                viewWidth = 1080,
                viewHeight = 1920,
            )
            val events = detector.onTwoFingersUp(eventTimeMs = (i * 300 + 50).toLong())
            assertEquals(1, events.size, "Tap $i must qualify as RightClick")
            assertInstanceOf(GestureEvent.RightClick::class.java, events[0])
            // reset() is called by onTwoFingersUp, so no explicit reset needed.
        }
    }

    @Test
    fun `onTwoFingersUp without prior down returns empty`() {
        // No onTwoFingersDown call — detector starts fresh, downCentroid=null.
        val events = detector.onTwoFingersUp(eventTimeMs = 100L)
        assertTrue(events.isEmpty(), "onTwoFingersUp without prior down must return empty list")
    }

    @Test
    fun `horizontal scroll emits correct deltaX and zero deltaY`() {
        detector.onTwoFingersDown(
            centroid = Offset(100f, 100f),
            spread = 200f,
            eventTimeMs = 0L,
            viewWidth = 1080,
            viewHeight = 1920,
        )

        val events =
            detector.onTwoFingersMove(
                centroid = Offset(150f, 100f),
                spread = 200f,
                eventTimeMs = 50L,
            )

        assertEquals(1, events.size)
        val scroll = assertInstanceOf(GestureEvent.Scroll::class.java, events[0])
        assertEquals(50.toShort(), scroll.deltaX)
        assertEquals(0.toShort(), scroll.deltaY)
    }
}
