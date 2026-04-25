package com.inkbridge.domain.model

/**
 * Port: receives stylus events from the capture layer and forwards them to the transport.
 *
 * Implementations handle encoding and sequencing internally. Callers are responsible for
 * providing correctly normalized [StylusSample] values.
 *
 * All functions are suspending so callers can back-pressure naturally on the coroutine
 * dispatcher without blocking the UI thread.
 */
interface StylusSink {
    /**
     * Emits a stylus position/pressure/tilt sample.
     * Called for both touch and hover moves.
     */
    suspend fun emit(sample: StylusSample)

    /**
     * Emits a proximity event (stylus entering or leaving the sensor range).
     *
     * @param entering true when the stylus enters proximity, false when it leaves.
     * @param timestampNs monotonic nanosecond timestamp.
     */
    suspend fun emitProximity(
        entering: Boolean,
        timestampNs: Long,
    )

    /**
     * Emits a button state-change event.
     *
     * @param primaryPressed   true when the primary barrel button is held.
     * @param secondaryPressed true when the secondary barrel button is held.
     * @param timestampNs      monotonic nanosecond timestamp.
     */
    suspend fun emitButton(
        primaryPressed: Boolean,
        secondaryPressed: Boolean,
        timestampNs: Long,
    )

    /**
     * Emits a two-finger scroll event.
     *
     * @param deltaX      Horizontal scroll delta in pixels (negative = left, positive = right).
     * @param deltaY      Vertical scroll delta in pixels.
     * @param phaseFlags  0x00 = continuation, 0x40 = begin, 0x80 = end (with empty deltas).
     *                    Used by macOS to construct began/changed/ended phase events and
     *                    momentum simulation after the gesture ends.
     * @param timestampNs Monotonic nanosecond timestamp.
     */
    suspend fun emitScroll(
        deltaX: Short,
        deltaY: Short,
        phaseFlags: UByte = 0x00u,
        timestampNs: Long,
    )

    /**
     * Emits a two-finger pinch/zoom event.
     *
     * @param scaleDelta  Multiplicative zoom factor since last frame. 1.0 = no change.
     * @param timestampNs Monotonic nanosecond timestamp.
     */
    suspend fun emitZoom(
        scaleDelta: Float,
        timestampNs: Long,
    )

    /**
     * Emits a single-finger trackpad-mode relative cursor movement.
     *
     * @param deltaX      Horizontal cursor delta in pixels (negative = left).
     * @param deltaY      Vertical cursor delta in pixels (negative = up).
     * @param timestampNs Monotonic nanosecond timestamp.
     */
    suspend fun emitCursorDelta(
        deltaX: Short,
        deltaY: Short,
        timestampNs: Long,
    )

    /**
     * Emits an express-key event (keyboard shortcut or modifier hold).
     *
     * @param keyCode   macOS virtual keycode (kVK_*) — 0u for modifier-only.
     * @param modifiers Bitfield: bit 0 Cmd, bit 1 Ctrl, bit 2 Opt, bit 3 Shift.
     * @param action    PRESS, RELEASE, or TAP.
     * @param timestampNs Monotonic nanosecond timestamp.
     */
    suspend fun emitKey(
        keyCode: UByte,
        modifiers: UByte,
        action: com.inkbridge.protocol.KeyAction,
        timestampNs: Long,
    )
}
