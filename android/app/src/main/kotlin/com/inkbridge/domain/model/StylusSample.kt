package com.inkbridge.domain.model

/**
 * A single captured stylus sample ready for encoding and transport.
 *
 * All fields are normalized / clamped by [com.inkbridge.data.capture.MotionEventMapper]
 * before this object is constructed. Validation guards catch programming errors only.
 *
 * @param x           Normalized X position in [0.0, 1.0].
 * @param y           Normalized Y position in [0.0, 1.0].
 * @param pressure    Raw u16 pressure [0, 65535]. 0 when no pressure sensor.
 * @param tiltX       Tilt component X, degrees × 100, range [−9000, 9000].
 * @param tiltY       Tilt component Y, degrees × 100, range [−9000, 9000].
 * @param hover       True when the stylus is hovering (not touching).
 * @param timestampNs Monotonic nanosecond timestamp from the Android device.
 */
data class StylusSample(
    val x: Float,
    val y: Float,
    val pressure: Int,
    val tiltX: Int,
    val tiltY: Int,
    val hover: Boolean,
    val timestampNs: Long,
) {
    init {
        require(x in 0f..1f) { "x must be in [0.0, 1.0] but was $x" }
        require(y in 0f..1f) { "y must be in [0.0, 1.0] but was $y" }
        require(pressure in 0..65535) { "pressure must be in [0, 65535] but was $pressure" }
        require(tiltX in -9000..9000) { "tiltX must be in [-9000, 9000] but was $tiltX" }
        require(tiltY in -9000..9000) { "tiltY must be in [-9000, 9000] but was $tiltY" }
    }
}
