package com.inkbridge.protocol

/**
 * Immutable header present in every InkBridge wire frame (16 bytes).
 *
 * Layout (little-endian, all fields contiguous):
 *   offset 0  – version      : u8
 *   offset 1  – eventType    : u8
 *   offset 2  – flags        : u8
 *   offset 3  – reserved     : u8 (must be 0x00 on send; ignore on receive)
 *   offset 4  – sequence     : u32 LE
 *   offset 8  – timestampNs  : u64 LE
 */
data class PacketHeader(
    val version: UByte,
    val eventType: UByte,
    val flags: UByte,
    val reserved: UByte,
    val sequence: UInt,
    val timestampNs: ULong,
)

/**
 * Flags bitfield constants (offset 2 of the wire header).
 */
object Flags {
    const val PRESSURE_PRESENT: UByte = 0x01u
    const val TILT_PRESENT: UByte = 0x02u
    const val HOVER: UByte = 0x04u
    const val BUTTON_PRIMARY: UByte = 0x08u
    const val BUTTON_SECONDARY: UByte = 0x10u

    /** Scroll/gesture phase markers — used in STYLUS_SCROLL frames. */
    const val SCROLL_BEGIN: UByte = 0x40u
    const val SCROLL_END: UByte = 0x80u
}

/**
 * Event type byte constants (offset 1 of the wire header).
 */
object EventType {
    const val STYLUS_MOVE: UByte = 0x01u
    const val STYLUS_PROXIMITY: UByte = 0x02u
    const val STYLUS_BUTTON: UByte = 0x03u
    const val STYLUS_SCROLL: UByte = 0x04u
    const val STYLUS_ZOOM: UByte = 0x05u
    const val CURSOR_DELTA: UByte = 0x06u
}

/**
 * Structured representation of a stylus event decoded from the wire format.
 * Each subtype carries the payload fields defined in wire-protocol.md R6–R8.
 */
sealed class StylusEvent {
    /**
     * STYLUS_MOVE (event_type = 0x01) — stylus tip touching or hovering with position data.
     * Payload: 20 bytes. Total frame: 36 bytes.
     *
     * @param x          Normalized X position in [0.0, 1.0].
     * @param y          Normalized Y position in [0.0, 1.0].
     * @param pressure   Raw u16 pressure [0, 65535]. 0 when PRESSURE_PRESENT is clear.
     * @param tiltX      Tilt around X axis × 100, range [−9000, 9000]. 0 when TILT_PRESENT clear.
     * @param tiltY      Tilt around Y axis × 100, range [−9000, 9000]. 0 when TILT_PRESENT clear.
     */
    data class Move(
        val x: Float,
        val y: Float,
        val pressure: UShort,
        val tiltX: Short,
        val tiltY: Short,
    ) : StylusEvent()

    /**
     * STYLUS_PROXIMITY (event_type = 0x02) — stylus entered or left the proximity zone.
     * Payload: 4 bytes. Total frame: 20 bytes.
     *
     * @param entering true = entering proximity (0x01); false = leaving (0x00).
     */
    data class Proximity(
        val entering: Boolean,
    ) : StylusEvent()

    /**
     * STYLUS_BUTTON (event_type = 0x03) — button state changed without movement.
     * Payload: 4 bytes. Total frame: 20 bytes.
     *
     * @param buttons Bitfield mirroring bits 3–4 of the header flags byte.
     *                Must be consistent with those bits or the frame is discarded.
     */
    data class Button(
        val buttons: UByte,
    ) : StylusEvent()

    /**
     * STYLUS_SCROLL (event_type = 0x04) — two-finger drag gesture scroll delta.
     * Payload: 4 bytes. Total frame: 20 bytes.
     *
     * @param deltaX Horizontal scroll delta in points (negative = left, positive = right).
     * @param deltaY Vertical scroll delta in points (negative = up, positive = down — sender
     *               uses raw direction; receiver applies natural-scroll inversion if configured).
     */
    data class Scroll(
        val deltaX: Short,
        val deltaY: Short,
    ) : StylusEvent()

    /**
     * STYLUS_ZOOM (event_type = 0x05) — two-finger pinch gesture zoom delta.
     * Payload: 4 bytes. Total frame: 20 bytes.
     *
     * @param scaleDelta Multiplicative zoom delta since last frame. 1.0 = no change.
     *                   Values > 1.0 = zoom in, < 1.0 = zoom out. Typical range 0.5..2.0.
     */
    data class Zoom(
        val scaleDelta: Float,
    ) : StylusEvent()

    /**
     * CURSOR_DELTA (event_type = 0x06) — relative cursor movement (trackpad mode).
     * Payload: 4 bytes. Total frame: 20 bytes.
     *
     * @param deltaX Horizontal cursor delta in points (negative = left, positive = right).
     * @param deltaY Vertical cursor delta in points (negative = up, positive = down).
     */
    data class CursorDelta(
        val deltaX: Short,
        val deltaY: Short,
    ) : StylusEvent()
}

/**
 * A successfully decoded wire frame: the parsed header plus the structured event payload.
 */
data class DecodedFrame(
    val header: PacketHeader,
    val event: StylusEvent,
)
