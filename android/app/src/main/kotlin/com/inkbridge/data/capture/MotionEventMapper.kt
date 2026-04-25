package com.inkbridge.data.capture

import com.inkbridge.domain.model.StylusSample
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.tan

/**
 * Maps [MotionEventLike] events into zero or more [StylusSample] values.
 *
 * Design rules (android-capture.md R1–R7):
 * - Only TOOL_TYPE_STYLUS and TOOL_TYPE_ERASER are processed (R1).
 * - x/y are normalized to [0, 1] relative to the view size and clamped (R2).
 * - Pressure from AXIS_PRESSURE is clamped to [0, 1] then mapped to u16 range (R3).
 * - Tilt from AXIS_TILT + AXIS_ORIENTATION is converted to Cartesian components
 *   clamped to [−9000, 9000] (R4).
 * - Button state from getButtonState() is read per sample (R5).
 * - ACTION_HOVER_* actions set hover=true (R6).
 * - Historical samples are emitted before the current sample in ascending order (R7).
 *
 * This class has no Android imports and is fully testable on a plain JVM.
 */
object MotionEventMapper {
    // RISK NOTE: The apply brief specifies tiltY = -cos(orientation)*tan(altitude)*100.
    // android-capture.md R4 specifies tiltY = cos(orientation)*tan(altitude)*100 (positive).
    // Specs are authoritative under SDD — using the spec formula (positive cos).
    // The user should verify tilt direction in an end-to-end test and adjust sign if needed.

    /**
     * Converts a single [MotionEventLike] into a list of [StylusSample] values.
     *
     * Returns an empty list for non-stylus events (R1).
     * Returns [n_historical + 1] samples for ACTION_MOVE events with batched history (R7).
     *
     * @param event the event to process.
     * @return ordered list of samples, oldest first.
     */
    fun map(event: MotionEventLike): List<StylusSample> {
        val toolType = event.getToolType()
        if (toolType != MotionEventLike.TOOL_TYPE_STYLUS &&
            toolType != MotionEventLike.TOOL_TYPE_ERASER
        ) {
            return emptyList()
        }

        val hover =
            when (event.action) {
                MotionEventLike.ACTION_HOVER_ENTER,
                MotionEventLike.ACTION_HOVER_MOVE,
                MotionEventLike.ACTION_HOVER_EXIT,
                -> true
                else -> false
            }

        val samples = mutableListOf<StylusSample>()

        // Emit historical samples first (R7 — ascending order, index 0 is oldest).
        val historySize = event.getHistorySize()
        for (i in 0 until historySize) {
            samples +=
                buildSample(
                    rawX = event.getHistoricalX(i),
                    rawY = event.getHistoricalY(i),
                    rawPressure = event.getHistoricalAxisValue(MotionEventLike.AXIS_PRESSURE, i),
                    rawTilt = event.getHistoricalAxisValue(MotionEventLike.AXIS_TILT, i),
                    rawOrientation = event.getHistoricalAxisValue(MotionEventLike.AXIS_ORIENTATION, i),
                    buttonState = event.getButtonState(),
                    hover = hover,
                    viewWidth = event.viewWidth,
                    viewHeight = event.viewHeight,
                    timestampNs = event.getHistoricalEventTime(i) * 1_000_000L,
                )
        }

        // Emit the current sample last.
        samples +=
            buildSample(
                rawX = event.getX(),
                rawY = event.getY(),
                rawPressure = event.getAxisValue(MotionEventLike.AXIS_PRESSURE),
                rawTilt = event.getAxisValue(MotionEventLike.AXIS_TILT),
                rawOrientation = event.getAxisValue(MotionEventLike.AXIS_ORIENTATION),
                buttonState = event.getButtonState(),
                hover = hover,
                viewWidth = event.viewWidth,
                viewHeight = event.viewHeight,
                timestampNs = event.eventTime * 1_000_000L,
            )

        return samples
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildSample(
        rawX: Float,
        rawY: Float,
        rawPressure: Float,
        rawTilt: Float,
        rawOrientation: Float,
        buttonState: Int,
        hover: Boolean,
        viewWidth: Int,
        viewHeight: Int,
        timestampNs: Long,
    ): StylusSample {
        // R2 — normalize and clamp position to [0, 1].
        val x = (rawX / viewWidth.toFloat()).coerceIn(0f, 1f)
        val y = (rawY / viewHeight.toFloat()).coerceIn(0f, 1f)

        // R3 — clamp pressure to [0, 1] then map to u16.
        val pressureFloat = rawPressure.coerceIn(0f, 1f)
        val pressure = (pressureFloat * 65535f).roundToInt().coerceIn(0, 65535)

        // R4 — convert AXIS_TILT (altitude from surface) + AXIS_ORIENTATION (azimuth) to Cartesian tilt.
        // altitude = π/2 - AXIS_TILT (altitude from surface → elevation above surface)
        // tilt_x = sin(orientation) × tan(altitude) × 100
        // tilt_y = cos(orientation) × tan(altitude) × 100  [spec-authoritative sign]
        val tiltX: Int
        val tiltY: Int
        if (rawTilt == 0f) {
            tiltX = 0
            tiltY = 0
        } else {
            val altitude = (PI / 2.0) - rawTilt.toDouble()
            val tanAlt = tan(altitude)
            tiltX =
                (sin(rawOrientation.toDouble()) * tanAlt * 100.0).roundToInt()
                    .coerceIn(-9000, 9000)
            tiltY =
                (cos(rawOrientation.toDouble()) * tanAlt * 100.0).roundToInt()
                    .coerceIn(-9000, 9000)
        }

        return StylusSample(
            x = x,
            y = y,
            pressure = pressure,
            tiltX = tiltX,
            tiltY = tiltY,
            hover = hover,
            timestampNs = timestampNs,
        )
    }
}
