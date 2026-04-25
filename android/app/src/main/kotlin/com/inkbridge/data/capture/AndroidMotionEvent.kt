package com.inkbridge.data.capture

import android.view.MotionEvent

/**
 * Production adapter: wraps a real [MotionEvent] and exposes it as [MotionEventLike].
 *
 * Lifetime: instantiated per event, never stored. The caller retains ownership of [event].
 *
 * @param event    The real Android MotionEvent.
 * @param viewWidth  The pixel width of the capture surface view.
 * @param viewHeight The pixel height of the capture surface view.
 */
class AndroidMotionEvent(
    private val event: MotionEvent,
    override val viewWidth: Int,
    override val viewHeight: Int,
) : MotionEventLike {
    override val action: Int
        get() = event.actionMasked

    override fun getToolType(): Int = event.getToolType(0)

    override fun getX(): Float = event.getX(0)

    override fun getY(): Float = event.getY(0)

    override fun getAxisValue(axis: Int): Float = event.getAxisValue(axis, 0)

    override fun getButtonState(): Int = event.buttonState

    override fun getHistorySize(): Int = event.historySize

    override fun getHistoricalX(pos: Int): Float = event.getHistoricalX(0, pos)

    override fun getHistoricalY(pos: Int): Float = event.getHistoricalY(0, pos)

    override fun getHistoricalAxisValue(
        axis: Int,
        pos: Int,
    ): Float = event.getHistoricalAxisValue(axis, 0, pos)

    override fun getHistoricalEventTime(pos: Int): Long = event.getHistoricalEventTime(pos)

    override val eventTime: Long
        get() = event.eventTime
}
