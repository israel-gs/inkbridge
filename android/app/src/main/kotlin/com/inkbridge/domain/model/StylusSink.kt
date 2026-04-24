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
    suspend fun emitProximity(entering: Boolean, timestampNs: Long)

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
}
