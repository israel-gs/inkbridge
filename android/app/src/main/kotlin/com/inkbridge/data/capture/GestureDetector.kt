package com.inkbridge.data.capture

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Represents the 2D position of the centroid of a two-finger touch cluster.
 *
 * Uses a simple data class rather than importing android.graphics.PointF to keep
 * this class pure Kotlin and testable without an Android runtime.
 */
data class Offset(val x: Float, val y: Float)

/**
 * Events emitted by [TwoFingerGestureDetector].
 */
sealed class GestureEvent {
    /** Two-finger drag: scroll by [deltaX], [deltaY] pixels (rounded to Short). */
    data class Scroll(val deltaX: Short, val deltaY: Short) : GestureEvent()

    /** Two-finger pinch: multiplicative scale delta since last frame. */
    data class Zoom(val scaleDelta: Float) : GestureEvent()

    /** Two-finger tap that qualified as a right-click. Centroid normalised to view bounds. */
    data class RightClick(val xNormalized: Float, val yNormalized: Float) : GestureEvent()
}

/**
 * Pure Kotlin gesture recognizer for two-finger touch events.
 *
 * Detects three gesture types from a stream of centroid+spread frames:
 * - **Scroll** — when the centroid moves more than a threshold per frame.
 * - **Zoom**   — when the spread (distance between fingers) changes more than a threshold.
 * - **Right-click** — when both fingers go down and up within [tapTimeoutMs]
 *   without total movement exceeding [tapMovementThresholdPx].
 *
 * No Android imports — can be unit-tested with plain JUnit 5 on the JVM.
 *
 * @param tapMovementThresholdPx  Cumulative movement (px) beyond which a tap is disqualified.
 * @param tapTimeoutMs            Max duration (ms) for a tap to qualify as a right-click.
 */
class TwoFingerGestureDetector(
    private val tapMovementThresholdPx: Float = 12f,
    private val tapTimeoutMs: Long = 150L,
) {

    // ── Internal state ────────────────────────────────────────────────────────

    private var prevCentroid: Offset? = null
    private var prevSpread: Float = 0f

    private var downCentroid: Offset? = null
    private var downTimeMs: Long = 0L
    private var cumulativeMovement: Float = 0f
    private var tapDisqualified: Boolean = false

    private var downViewWidth: Int = 1
    private var downViewHeight: Int = 1

    // Movement thresholds
    private val scrollThresholdPx = 1.5f
    private val zoomThreshold = 0.005f

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Call when exactly two fingers touch down simultaneously.
     *
     * @param centroid     Position of the midpoint between the two fingers.
     * @param spread       Distance between the two fingers in pixels.
     * @param eventTimeMs  Monotonic event timestamp in milliseconds.
     * @param viewWidth    Width of the capture view (used to normalise tap position).
     * @param viewHeight   Height of the capture view.
     */
    fun onTwoFingersDown(
        centroid: Offset,
        spread: Float,
        eventTimeMs: Long,
        viewWidth: Int,
        viewHeight: Int,
    ) {
        prevCentroid = centroid
        prevSpread = spread
        downCentroid = centroid
        downTimeMs = eventTimeMs
        cumulativeMovement = 0f
        tapDisqualified = false
        downViewWidth = viewWidth.coerceAtLeast(1)
        downViewHeight = viewHeight.coerceAtLeast(1)
    }

    /**
     * Call on every move event with two fingers in contact.
     *
     * May emit Scroll and/or Zoom events in a single call when both centroid movement
     * and spread change exceed their respective thresholds.
     *
     * @return List of [GestureEvent]s (may be empty, may contain one or both types).
     */
    fun onTwoFingersMove(
        centroid: Offset,
        spread: Float,
        eventTimeMs: Long,
    ): List<GestureEvent> {
        val prev = prevCentroid ?: run {
            prevCentroid = centroid
            prevSpread = spread
            return emptyList()
        }

        val dx = centroid.x - prev.x
        val dy = centroid.y - prev.y
        val movement = sqrt(dx * dx + dy * dy)

        // Accumulate total movement for tap qualification.
        cumulativeMovement += movement
        if (cumulativeMovement > tapMovementThresholdPx) {
            tapDisqualified = true
        }

        val events = mutableListOf<GestureEvent>()

        // Scroll: emit if centroid moved more than threshold.
        if (movement > scrollThresholdPx) {
            val clampedDx = dx.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
            val clampedDy = dy.coerceIn(Short.MIN_VALUE.toFloat(), Short.MAX_VALUE.toFloat()).toInt().toShort()
            events.add(GestureEvent.Scroll(deltaX = clampedDx, deltaY = clampedDy))
        }

        // Zoom: emit if spread ratio changed beyond threshold.
        if (prevSpread > 0f) {
            val scaleDelta = spread / prevSpread
            if (abs(scaleDelta - 1.0f) > zoomThreshold) {
                events.add(GestureEvent.Zoom(scaleDelta = scaleDelta))
            }
        }

        prevCentroid = centroid
        prevSpread = spread

        return events
    }

    /**
     * Call when both fingers lift.
     *
     * May emit a [GestureEvent.RightClick] if the gesture qualified as a tap.
     *
     * @return List containing [GestureEvent.RightClick] if the tap qualified; otherwise empty.
     */
    fun onTwoFingersUp(eventTimeMs: Long): List<GestureEvent> {
        val down = downCentroid
        val elapsed = eventTimeMs - downTimeMs
        val wasDisqualified = tapDisqualified
        val w = downViewWidth
        val h = downViewHeight

        reset()

        if (down != null && !wasDisqualified && elapsed < tapTimeoutMs) {
            val xNorm = (down.x / w).coerceIn(0f, 1f)
            val yNorm = (down.y / h).coerceIn(0f, 1f)
            return listOf(GestureEvent.RightClick(xNormalized = xNorm, yNormalized = yNorm))
        }
        return emptyList()
    }

    /**
     * Discard all in-progress gesture state. Call when the gesture is interrupted
     * (e.g. third finger touches, focus lost, connection dropped).
     */
    fun reset() {
        prevCentroid = null
        prevSpread = 0f
        downCentroid = null
        downTimeMs = 0L
        cumulativeMovement = 0f
        tapDisqualified = false
    }
}
