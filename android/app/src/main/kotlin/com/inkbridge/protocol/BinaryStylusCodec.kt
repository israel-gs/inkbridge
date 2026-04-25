package com.inkbridge.protocol

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Stateless codec for the InkBridge binary wire protocol v1.
 *
 * Encodes [StylusEvent] instances to [ByteArray] and decodes [ByteArray] back to [DecodedFrame].
 * Zero Android-API dependencies — runs on any JVM (testable with plain JUnit 5).
 *
 * Wire format reference: openspec/changes/foundation/specs/wire-protocol.md R1–R13.
 *
 * Byte order: little-endian throughout (R1).
 * Header: 16 bytes fixed (R3).
 * Payload sizes:
 *   STYLUS_MOVE      (0x01) → 20 bytes payload → 36 bytes total (R6)
 *   STYLUS_PROXIMITY (0x02) → 4 bytes payload  → 20 bytes total (R7)
 *   STYLUS_BUTTON    (0x03) → 4 bytes payload  → 20 bytes total (R8)
 *   STYLUS_SCROLL    (0x04) → 4 bytes payload  → 20 bytes total (R12)
 *   STYLUS_ZOOM      (0x05) → 4 bytes payload  → 20 bytes total (R13)
 */
object BinaryStylusCodec {

    private const val PROTOCOL_VERSION: Byte = 0x01
    private const val HEADER_SIZE = 16
    private const val MOVE_PAYLOAD_SIZE = 20
    private const val PROX_BUTTON_PAYLOAD_SIZE = 4
    private const val SCROLL_ZOOM_PAYLOAD_SIZE = 4

    // ─────────────────────────────────────────────────────────────
    // Encode
    // ─────────────────────────────────────────────────────────────

    /**
     * Encodes a [StylusEvent] into a wire-format [ByteArray].
     *
     * @param event        The stylus event to encode.
     * @param flags        The flags byte to write at header offset 2 (R5).
     *                     Callers are responsible for setting PRESSURE_PRESENT, TILT_PRESENT,
     *                     HOVER, BUTTON_PRIMARY, BUTTON_SECONDARY bits correctly.
     * @param sequence     Per-session monotonic counter; wraps at 2^32 (R9).
     * @param timestampNs  Monotonic nanosecond timestamp from the Android device (R3).
     * @return Encoded byte array (36 bytes for MOVE, 20 bytes for PROXIMITY/BUTTON).
     */
    fun encode(
        event: StylusEvent,
        flags: UByte,
        sequence: UInt,
        timestampNs: ULong,
    ): ByteArray {
        val eventTypeByte: Byte
        val payloadSize: Int
        val writePayload: (ByteBuffer) -> Unit

        when (event) {
            is StylusEvent.Move -> {
                eventTypeByte = EventType.STYLUS_MOVE.toByte()
                payloadSize = MOVE_PAYLOAD_SIZE
                writePayload = { buf -> writeMovePayload(buf, event) }
            }
            is StylusEvent.Proximity -> {
                eventTypeByte = EventType.STYLUS_PROXIMITY.toByte()
                payloadSize = PROX_BUTTON_PAYLOAD_SIZE
                writePayload = { buf -> writeProximityPayload(buf, event) }
            }
            is StylusEvent.Button -> {
                eventTypeByte = EventType.STYLUS_BUTTON.toByte()
                payloadSize = PROX_BUTTON_PAYLOAD_SIZE
                writePayload = { buf -> writeButtonPayload(buf, event) }
            }
            is StylusEvent.Scroll -> {
                eventTypeByte = EventType.STYLUS_SCROLL.toByte()
                payloadSize = SCROLL_ZOOM_PAYLOAD_SIZE
                writePayload = { buf -> writeScrollPayload(buf, event) }
            }
            is StylusEvent.Zoom -> {
                eventTypeByte = EventType.STYLUS_ZOOM.toByte()
                payloadSize = SCROLL_ZOOM_PAYLOAD_SIZE
                writePayload = { buf -> writeZoomPayload(buf, event) }
            }
            is StylusEvent.CursorDelta -> {
                eventTypeByte = EventType.CURSOR_DELTA.toByte()
                payloadSize = SCROLL_ZOOM_PAYLOAD_SIZE
                writePayload = { buf -> writeCursorDeltaPayload(buf, event) }
            }
        }

        val buf = ByteBuffer.allocate(HEADER_SIZE + payloadSize).order(ByteOrder.LITTLE_ENDIAN)
        writeHeader(buf, eventTypeByte, flags, sequence, timestampNs)
        writePayload(buf)
        return buf.array()
    }

    private fun writeHeader(
        buf: ByteBuffer,
        eventTypeByte: Byte,
        flags: UByte,
        sequence: UInt,
        timestampNs: ULong,
    ) {
        buf.put(PROTOCOL_VERSION)           // offset 0: version
        buf.put(eventTypeByte)              // offset 1: event_type
        buf.put(flags.toByte())             // offset 2: flags
        buf.put(0x00)                       // offset 3: _reserved (MUST be 0x00)
        buf.putInt(sequence.toInt())        // offset 4–7: sequence u32 LE
        buf.putLong(timestampNs.toLong())   // offset 8–15: timestamp_ns u64 LE
    }

    private fun writeMovePayload(buf: ByteBuffer, event: StylusEvent.Move) {
        // Clamp x and y to [0.0, 1.0] per R6.
        buf.putFloat(event.x.coerceIn(0f, 1f))      // offset 16–19: x f32 LE
        buf.putFloat(event.y.coerceIn(0f, 1f))      // offset 20–23: y f32 LE
        buf.putShort(event.pressure.toShort())       // offset 24–25: pressure u16 LE
        buf.putShort(event.tiltX)                    // offset 26–27: tilt_x i16 LE
        buf.putShort(event.tiltY)                    // offset 28–29: tilt_y i16 LE
        buf.putShort(0)                              // offset 30–31: _pad = 0x0000
        buf.putInt(0)                                // offset 32–35: _reserved = 0x00000000
    }

    private fun writeProximityPayload(buf: ByteBuffer, event: StylusEvent.Proximity) {
        buf.put(if (event.entering) 0x01 else 0x00) // offset 16: entering
        buf.put(0x00)                               // offset 17: _pad[0]
        buf.put(0x00)                               // offset 18: _pad[1]
        buf.put(0x00)                               // offset 19: _pad[2]
    }

    private fun writeButtonPayload(buf: ByteBuffer, event: StylusEvent.Button) {
        buf.put(event.buttons.toByte())             // offset 16: buttons
        buf.put(0x00)                               // offset 17: _pad[0]
        buf.put(0x00)                               // offset 18: _pad[1]
        buf.put(0x00)                               // offset 19: _pad[2]
    }

    private fun writeScrollPayload(buf: ByteBuffer, event: StylusEvent.Scroll) {
        buf.putShort(event.deltaX)                  // offset 16–17: delta_x i16 LE
        buf.putShort(event.deltaY)                  // offset 18–19: delta_y i16 LE
    }

    private fun writeZoomPayload(buf: ByteBuffer, event: StylusEvent.Zoom) {
        buf.putFloat(event.scaleDelta)              // offset 16–19: scale_delta f32 LE
    }

    private fun writeCursorDeltaPayload(buf: ByteBuffer, event: StylusEvent.CursorDelta) {
        buf.putShort(event.deltaX)                  // offset 16–17: delta_x i16 LE
        buf.putShort(event.deltaY)                  // offset 18–19: delta_y i16 LE
    }

    // ─────────────────────────────────────────────────────────────
    // Decode
    // ─────────────────────────────────────────────────────────────

    /**
     * Decodes a wire-format [ByteArray] into a [DecodedFrame].
     *
     * Forward-compatible per R11: trailing bytes beyond the known payload size are silently ignored.
     *
     * @throws ProtocolException if:
     *   - The array is shorter than the 16-byte header.
     *   - The version byte at offset 0 is not 0x01 (R2).
     *   - The event_type at offset 1 is not 0x01, 0x02, or 0x03 (R4).
     *   - The array is shorter than the expected frame size for the declared event_type.
     *   - For STYLUS_BUTTON: the buttons payload byte is inconsistent with flags bits 3–4 (R8).
     */
    fun decode(bytes: ByteArray): DecodedFrame {
        if (bytes.size < HEADER_SIZE) {
            throw ProtocolException(
                "Frame too short: expected at least $HEADER_SIZE header bytes, got ${bytes.size}",
            )
        }

        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)

        val version = buf.get().toUByte()
        if (version != 1u.toUByte()) {
            throw ProtocolException("Unknown protocol version: 0x${version.toString(16).uppercase()}")
        }

        val eventType = buf.get().toUByte()
        val flags = buf.get().toUByte()
        val reserved = buf.get().toUByte()
        val sequence = buf.getInt().toUInt()
        val timestampNs = buf.getLong().toULong()

        val header = PacketHeader(
            version = version,
            eventType = eventType,
            flags = flags,
            reserved = reserved,
            sequence = sequence,
            timestampNs = timestampNs,
        )

        val event = when (eventType) {
            EventType.STYLUS_MOVE -> decodeMovePayload(bytes, buf)
            EventType.STYLUS_PROXIMITY -> decodeProximityPayload(bytes, buf)
            EventType.STYLUS_BUTTON -> decodeButtonPayload(bytes, buf, flags)
            EventType.STYLUS_SCROLL -> decodeScrollPayload(bytes, buf)
            EventType.STYLUS_ZOOM -> decodeZoomPayload(bytes, buf)
            EventType.CURSOR_DELTA -> decodeCursorDeltaPayload(bytes, buf)
            else -> throw ProtocolException(
                "Unknown event_type: 0x${eventType.toString(16).uppercase()}",
            )
        }

        return DecodedFrame(header = header, event = event)
    }

    private fun decodeMovePayload(bytes: ByteArray, buf: ByteBuffer): StylusEvent.Move {
        val required = HEADER_SIZE + MOVE_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "STYLUS_MOVE frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val x = buf.getFloat()
        val y = buf.getFloat()
        val pressure = buf.getShort().toUShort()
        val tiltX = buf.getShort()
        val tiltY = buf.getShort()
        // _pad (2 bytes) and _reserved (4 bytes) are read and discarded per R6.
        // Remaining bytes beyond offset 36 are ignored per R11.
        return StylusEvent.Move(x = x, y = y, pressure = pressure, tiltX = tiltX, tiltY = tiltY)
    }

    private fun decodeProximityPayload(bytes: ByteArray, buf: ByteBuffer): StylusEvent.Proximity {
        val required = HEADER_SIZE + PROX_BUTTON_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "STYLUS_PROXIMITY frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val entering = buf.get().toInt() != 0
        // _pad 3 bytes are read and discarded.
        return StylusEvent.Proximity(entering = entering)
    }

    private fun decodeButtonPayload(
        bytes: ByteArray,
        buf: ByteBuffer,
        flags: UByte,
    ): StylusEvent.Button {
        val required = HEADER_SIZE + PROX_BUTTON_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "STYLUS_BUTTON frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val buttonsByte = buf.get().toUByte()

        // R8: buttons payload must be consistent with bits 3–4 of the header flags byte.
        // Extract bits 3–4 from flags (mask = 0x18) and compare with buttons.
        val flagsBits34 = (flags and 0x18u.toUByte())
        if (buttonsByte != flagsBits34) {
            throw ProtocolException(
                "STYLUS_BUTTON buttons payload 0x${buttonsByte.toString(16).uppercase()} " +
                    "is inconsistent with flags bits 3-4: 0x${flagsBits34.toString(16).uppercase()}",
            )
        }
        return StylusEvent.Button(buttons = buttonsByte)
    }

    private fun decodeScrollPayload(bytes: ByteArray, buf: ByteBuffer): StylusEvent.Scroll {
        val required = HEADER_SIZE + SCROLL_ZOOM_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "STYLUS_SCROLL frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val deltaX = buf.getShort()   // offset 16–17: delta_x i16 LE
        val deltaY = buf.getShort()   // offset 18–19: delta_y i16 LE
        return StylusEvent.Scroll(deltaX = deltaX, deltaY = deltaY)
    }

    private fun decodeZoomPayload(bytes: ByteArray, buf: ByteBuffer): StylusEvent.Zoom {
        val required = HEADER_SIZE + SCROLL_ZOOM_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "STYLUS_ZOOM frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val scaleDelta = buf.getFloat()   // offset 16–19: scale_delta f32 LE
        return StylusEvent.Zoom(scaleDelta = scaleDelta)
    }

    private fun decodeCursorDeltaPayload(bytes: ByteArray, buf: ByteBuffer): StylusEvent.CursorDelta {
        val required = HEADER_SIZE + SCROLL_ZOOM_PAYLOAD_SIZE
        if (bytes.size < required) {
            throw ProtocolException(
                "CURSOR_DELTA frame too short: expected at least $required bytes, got ${bytes.size}",
            )
        }
        val deltaX = buf.getShort()
        val deltaY = buf.getShort()
        return StylusEvent.CursorDelta(deltaX = deltaX, deltaY = deltaY)
    }
}
