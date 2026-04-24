package com.inkbridge.data.capture

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

/**
 * Unit tests for [MotionEventMapper].
 *
 * All tests use [FakeMotionEvent] — zero Android API dependency.
 * Covers android-capture.md R1–R7 scenarios.
 */
class MotionEventMapperTest {

    // ── Fake ─────────────────────────────────────────────────────────────────

    /**
     * Mutable test double for [MotionEventLike].
     * Set fields before passing to [MotionEventMapper.map].
     */
    private class FakeMotionEvent(
        override val action: Int = MotionEventLike.ACTION_MOVE,
        override val viewWidth: Int = 1080,
        override val viewHeight: Int = 2400,
        private val toolType: Int = MotionEventLike.TOOL_TYPE_STYLUS,
        private val x: Float = 540f,
        private val y: Float = 1200f,
        private val pressure: Float = 0.5f,
        private val tilt: Float = 0f,
        private val orientation: Float = 0f,
        private val buttonState: Int = 0,
        override val eventTime: Long = 1000L,
        private val historicalX: List<Float> = emptyList(),
        private val historicalY: List<Float> = emptyList(),
        private val historicalPressure: List<Float> = emptyList(),
        private val historicalTilt: List<Float> = emptyList(),
        private val historicalOrientation: List<Float> = emptyList(),
        private val historicalEventTime: List<Long> = emptyList(),
    ) : MotionEventLike {
        override fun getToolType(): Int = toolType
        override fun getX(): Float = x
        override fun getY(): Float = y
        override fun getAxisValue(axis: Int): Float = when (axis) {
            MotionEventLike.AXIS_PRESSURE -> pressure
            MotionEventLike.AXIS_TILT -> tilt
            MotionEventLike.AXIS_ORIENTATION -> orientation
            else -> 0f
        }
        override fun getButtonState(): Int = buttonState
        override fun getHistorySize(): Int = historicalX.size
        override fun getHistoricalX(pos: Int): Float = historicalX[pos]
        override fun getHistoricalY(pos: Int): Float = historicalY[pos]
        override fun getHistoricalAxisValue(axis: Int, pos: Int): Float = when (axis) {
            MotionEventLike.AXIS_PRESSURE -> historicalPressure.getOrElse(pos) { 0f }
            MotionEventLike.AXIS_TILT -> historicalTilt.getOrElse(pos) { 0f }
            MotionEventLike.AXIS_ORIENTATION -> historicalOrientation.getOrElse(pos) { 0f }
            else -> 0f
        }
        override fun getHistoricalEventTime(pos: Int): Long = historicalEventTime.getOrElse(pos) { 0L }
    }

    // ── R1: Stylus-only filter ────────────────────────────────────────────────

    @Test
    fun `finger touch produces no samples`() {
        val ev = FakeMotionEvent(toolType = MotionEventLike.TOOL_TYPE_FINGER)
        assertTrue(MotionEventMapper.map(ev).isEmpty(), "Finger events must be filtered out")
    }

    @Test
    fun `mouse event produces no samples`() {
        val ev = FakeMotionEvent(toolType = MotionEventLike.TOOL_TYPE_MOUSE)
        assertTrue(MotionEventMapper.map(ev).isEmpty())
    }

    @Test
    fun `unknown tool type produces no samples`() {
        val ev = FakeMotionEvent(toolType = MotionEventLike.TOOL_TYPE_UNKNOWN)
        assertTrue(MotionEventMapper.map(ev).isEmpty())
    }

    @Test
    fun `stylus tool type produces one sample`() {
        val ev = FakeMotionEvent(toolType = MotionEventLike.TOOL_TYPE_STYLUS)
        assertEquals(1, MotionEventMapper.map(ev).size)
    }

    @Test
    fun `eraser tool type produces one sample`() {
        val ev = FakeMotionEvent(toolType = MotionEventLike.TOOL_TYPE_ERASER)
        assertEquals(1, MotionEventMapper.map(ev).size)
    }

    // ── R2: Position normalization ────────────────────────────────────────────

    @Test
    fun `center position normalizes to 0,5 x 0,5`() {
        val ev = FakeMotionEvent(x = 540f, y = 1200f, viewWidth = 1080, viewHeight = 2400)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(0.5f, sample.x, 1e-6f)
        assertEquals(0.5f, sample.y, 1e-6f)
    }

    @Test
    fun `negative x is clamped to 0`() {
        val ev = FakeMotionEvent(x = -2f, y = 0f, viewWidth = 1080, viewHeight = 2400)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(0f, sample.x, 1e-6f)
    }

    @Test
    fun `x beyond view width is clamped to 1`() {
        val ev = FakeMotionEvent(x = 1200f, y = 0f, viewWidth = 1080, viewHeight = 2400)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(1f, sample.x, 1e-6f)
    }

    @Test
    fun `y beyond view height is clamped to 1`() {
        val ev = FakeMotionEvent(x = 0f, y = 2500f, viewWidth = 1080, viewHeight = 2400)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(1f, sample.y, 1e-6f)
    }

    // ── R3: Pressure ─────────────────────────────────────────────────────────

    @Test
    fun `pressure 1,0 maps to 65535`() {
        val ev = FakeMotionEvent(pressure = 1.0f)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(65535, sample.pressure)
    }

    @Test
    fun `pressure 0,0 maps to 0`() {
        val ev = FakeMotionEvent(pressure = 0.0f)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(0, sample.pressure)
    }

    @Test
    fun `pressure 0,75 maps to 49151`() {
        val ev = FakeMotionEvent(pressure = 0.75f)
        val sample = MotionEventMapper.map(ev).single()
        // round(0.75 × 65535) = round(49151.25) = 49151
        assertEquals(49151, sample.pressure)
    }

    @Test
    fun `pressure above 1 is clamped before mapping`() {
        val ev = FakeMotionEvent(pressure = 1.5f)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(65535, sample.pressure)
    }

    // ── R4: Tilt ─────────────────────────────────────────────────────────────

    @Test
    fun `tilt zero produces tiltX=0 tiltY=0`() {
        val ev = FakeMotionEvent(tilt = 0f, orientation = 0f)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(0, sample.tiltX)
        assertEquals(0, sample.tiltY)
    }

    @Test
    fun `tilt 45deg orientation 0 produces correct cartesian components`() {
        // AXIS_TILT = π/4 (45°), AXIS_ORIENTATION = 0
        // altitude = π/2 - π/4 = π/4
        // tiltX = sin(0) × tan(π/4) × 100 = 0 × 1 × 100 = 0
        // tiltY = cos(0) × tan(π/4) × 100 = 1 × 1 × 100 = 100
        val ev = FakeMotionEvent(tilt = (PI / 4).toFloat(), orientation = 0f)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(0, sample.tiltX)
        assertEquals(100, sample.tiltY)
    }

    @Test
    fun `tilt 45deg orientation 90deg produces tiltX=100 tiltY=0`() {
        // AXIS_TILT = π/4, AXIS_ORIENTATION = π/2
        // tiltX = sin(π/2) × tan(π/4) × 100 = 1 × 1 × 100 = 100
        // tiltY = cos(π/2) × tan(π/4) × 100 ≈ 0 × 1 × 100 = 0
        val ev = FakeMotionEvent(tilt = (PI / 4).toFloat(), orientation = (PI / 2).toFloat())
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(100, sample.tiltX)
        // cos(π/2) is near 0 but not exactly 0 in floating point; allow ±1
        assertTrue(sample.tiltY in -1..1, "tiltY should be near 0, got ${sample.tiltY}")
    }

    @Test
    fun `tilt components are clamped to 9000`() {
        // Near-horizontal stylus: AXIS_TILT ≈ π/2 → altitude ≈ 0 → tan(altitude) → very large
        val ev = FakeMotionEvent(tilt = (PI / 2 - 0.001).toFloat(), orientation = 0f)
        val sample = MotionEventMapper.map(ev).single()
        assertTrue(sample.tiltX in -9000..9000)
        assertTrue(sample.tiltY in -9000..9000)
    }

    // ── R6: Hover ────────────────────────────────────────────────────────────

    @Test
    fun `ACTION_HOVER_ENTER sets hover=true`() {
        val ev = FakeMotionEvent(action = MotionEventLike.ACTION_HOVER_ENTER)
        val sample = MotionEventMapper.map(ev).single()
        assertTrue(sample.hover)
    }

    @Test
    fun `ACTION_HOVER_MOVE sets hover=true`() {
        val ev = FakeMotionEvent(action = MotionEventLike.ACTION_HOVER_MOVE)
        val sample = MotionEventMapper.map(ev).single()
        assertTrue(sample.hover)
    }

    @Test
    fun `ACTION_HOVER_EXIT sets hover=true`() {
        // Hover flag is set on the exit event itself; the StylusSink handles PROX_EXIT separately.
        val ev = FakeMotionEvent(action = MotionEventLike.ACTION_HOVER_EXIT)
        val sample = MotionEventMapper.map(ev).single()
        assertTrue(sample.hover)
    }

    @Test
    fun `ACTION_MOVE does not set hover`() {
        val ev = FakeMotionEvent(action = MotionEventLike.ACTION_MOVE)
        val sample = MotionEventMapper.map(ev).single()
        assertEquals(false, sample.hover)
    }

    // ── R7: Historical batching ───────────────────────────────────────────────

    @Test
    fun `event with 3 historical samples produces 4 ordered samples`() {
        // 3 historical + 1 current = 4 total
        val ev = FakeMotionEvent(
            x = 840f, y = 1800f,
            historicalX = listOf(100f, 200f, 300f),
            historicalY = listOf(200f, 400f, 600f),
            historicalPressure = listOf(0.1f, 0.2f, 0.3f),
            historicalTilt = listOf(0f, 0f, 0f),
            historicalOrientation = listOf(0f, 0f, 0f),
            historicalEventTime = listOf(100L, 200L, 300L),
        )
        val samples = MotionEventMapper.map(ev)
        assertEquals(4, samples.size, "Must produce 4 samples (3 historical + 1 current)")

        // Historical samples in ascending order (oldest first = index 0)
        assertEquals(100f / 1080f, samples[0].x, 1e-5f) // historical[0].x = 100/1080
        assertEquals(200f / 1080f, samples[1].x, 1e-5f) // historical[1].x = 200/1080
        assertEquals(300f / 1080f, samples[2].x, 1e-5f) // historical[2].x = 300/1080

        // Current sample is last
        assertEquals((840f / 1080f), samples[3].x, 1e-5f)
    }

    @Test
    fun `historical sample timestamps are converted from ms to ns`() {
        val ev = FakeMotionEvent(
            historicalX = listOf(100f),
            historicalY = listOf(100f),
            historicalEventTime = listOf(500L),
            eventTime = 1000L,
        )
        val samples = MotionEventMapper.map(ev)
        assertEquals(2, samples.size)
        assertEquals(500L * 1_000_000L, samples[0].timestampNs)
        assertEquals(1000L * 1_000_000L, samples[1].timestampNs)
    }

    @Test
    fun `event without history produces exactly one sample`() {
        val ev = FakeMotionEvent()
        assertEquals(1, MotionEventMapper.map(ev).size)
    }
}
