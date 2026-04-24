package com.inkbridge.data.capture

/**
 * Structural interface over [android.view.MotionEvent] that exposes exactly the
 * axes and actions consumed by [MotionEventMapper].
 *
 * Production code wraps the real MotionEvent via [AndroidMotionEvent].
 * Tests implement this interface directly with fake values — zero Android API dependency.
 *
 * Axis constants mirror android.view.MotionEvent values and are reproduced here
 * so this file compiles in the plain-JVM test source set.
 */
interface MotionEventLike {

    companion object {
        // Tool type constants — mirrors android.view.MotionEvent
        const val TOOL_TYPE_UNKNOWN: Int = 0
        const val TOOL_TYPE_FINGER: Int = 1
        const val TOOL_TYPE_STYLUS: Int = 2
        const val TOOL_TYPE_MOUSE: Int = 3
        const val TOOL_TYPE_ERASER: Int = 4

        // Action constants — mirrors android.view.MotionEvent
        const val ACTION_DOWN: Int = 0
        const val ACTION_UP: Int = 1
        const val ACTION_MOVE: Int = 2
        const val ACTION_CANCEL: Int = 3
        const val ACTION_HOVER_ENTER: Int = 9
        const val ACTION_HOVER_MOVE: Int = 7
        const val ACTION_HOVER_EXIT: Int = 10

        // Axis constants — mirrors android.view.MotionEvent
        const val AXIS_PRESSURE: Int = 2
        const val AXIS_TILT: Int = 25
        const val AXIS_ORIENTATION: Int = 8

        // Button constants — mirrors android.view.MotionEvent
        const val BUTTON_STYLUS_PRIMARY: Int = 32
        const val BUTTON_STYLUS_SECONDARY: Int = 64
    }

    /** Returns the action code (masked). */
    val action: Int

    /** View width used for x normalization. Must be > 0. */
    val viewWidth: Int

    /** View height used for y normalization. Must be > 0. */
    val viewHeight: Int

    /** Tool type for pointer index 0. */
    fun getToolType(): Int

    /** Raw X coordinate for the current (non-historical) sample. */
    fun getX(): Float

    /** Raw Y coordinate for the current (non-historical) sample. */
    fun getY(): Float

    /** Raw axis value for the current sample. */
    fun getAxisValue(axis: Int): Float

    /** Combined button state bitmask. */
    fun getButtonState(): Int

    /** Number of historical (batched) samples in this event. */
    fun getHistorySize(): Int

    /** Raw X coordinate for historical sample at [pos]. */
    fun getHistoricalX(pos: Int): Float

    /** Raw Y coordinate for historical sample at [pos]. */
    fun getHistoricalY(pos: Int): Float

    /** Raw axis value for historical sample at [pos]. */
    fun getHistoricalAxisValue(axis: Int, pos: Int): Float

    /** Event time in ms for historical sample at [pos] (used to compute timestampNs). */
    fun getHistoricalEventTime(pos: Int): Long

    /** Event time in ms for the current (non-historical) sample. */
    val eventTime: Long
}
