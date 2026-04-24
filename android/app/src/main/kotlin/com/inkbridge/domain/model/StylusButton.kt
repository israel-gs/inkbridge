package com.inkbridge.domain.model

/**
 * Barrel-button identifiers for stylus hardware.
 *
 * Maps to the BUTTON_PRIMARY / BUTTON_SECONDARY flag bits in the wire protocol
 * (wire-protocol.md R5, bits 3–4) and to Android's MotionEvent button constants
 * (android-capture.md R5).
 */
enum class StylusButton {
    /** Primary barrel button — MotionEvent.BUTTON_STYLUS_PRIMARY. */
    PRIMARY,

    /** Secondary barrel button — MotionEvent.BUTTON_STYLUS_SECONDARY. */
    SECONDARY,

    /** Eraser end of a reversible stylus (tool type TOOL_TYPE_ERASER). */
    ERASER,
}
