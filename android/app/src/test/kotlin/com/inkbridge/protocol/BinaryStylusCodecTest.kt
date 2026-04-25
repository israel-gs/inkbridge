package com.inkbridge.protocol

import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/**
 * Unit tests for [BinaryStylusCodec] following the TDD red-green-refactor cycle.
 *
 * Test vectors are loaded at runtime from the build directory where Gradle copies them.
 * The Gradle task `copyProtocolVectors` (wired to processTestResources) copies
 * protocol/test-vectors → build/resources/test/vectors before `test` runs.
 *
 * Vectors are the single source of truth for interop between Kotlin and Swift codecs.
 *
 * Wire-protocol.md references: R1 (LE), R2 (version), R3 (header), R4 (event_type),
 * R5 (flags), R6 (MOVE payload), R7 (PROXIMITY payload), R8 (BUTTON payload), R9 (sequence).
 */
class BinaryStylusCodecTest {
    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────

    /**
     * Loads a hex test vector from the classpath (resources/test/vectors/).
     * Format: one line of uppercase space-separated hex pairs; lines starting with `#` are comments.
     */
    private fun loadVector(filename: String): ByteArray {
        val stream =
            checkNotNull(
                javaClass.classLoader?.getResourceAsStream("vectors/$filename"),
            ) {
                "Test vector not found: vectors/$filename — run `./gradlew test` (copyProtocolVectors must run first)"
            }
        return stream.bufferedReader().useLines { lines ->
            lines
                .filterNot { it.trimStart().startsWith('#') }
                .flatMap { it.trim().split(Regex("\\s+")) }
                .filter { it.isNotEmpty() }
                .map { it.toInt(16).toByte() }
                .toList()
                .toByteArray()
        }
    }

    private val codec = BinaryStylusCodec

    // ─────────────────────────────────────────────────────────────
    // Decode: vector-matching tests (R6–R8, R10)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode move vector matches expected StylusEvent Move`() {
        // Vector: move-with-pressure-tilt.hex
        // version=1, event_type=0x01, flags=0x03 (PRESSURE_PRESENT|TILT_PRESENT)
        // sequence=42, timestamp_ns=8_000_000_000
        // x=0.5, y=0.25, pressure=49151, tilt_x=4500, tilt_y=-1800
        val bytes = loadVector("move-with-pressure-tilt.hex")
        assertEquals(36, bytes.size, "STYLUS_MOVE frame must be 36 bytes")

        val frame = codec.decode(bytes)

        // Header assertions
        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_MOVE, frame.header.eventType)
        assertEquals(0x03u.toUByte(), frame.header.flags) // PRESSURE_PRESENT | TILT_PRESENT
        assertEquals(42u, frame.header.sequence)
        assertEquals(8_000_000_000uL, frame.header.timestampNs)

        // Payload assertions
        val move = assertInstanceOf(StylusEvent.Move::class.java, frame.event)
        assertEquals(0.5f, move.x, 1e-6f)
        assertEquals(0.25f, move.y, 1e-6f)
        assertEquals(49151u.toUShort(), move.pressure)
        assertEquals(4500.toShort(), move.tiltX)
        assertEquals((-1800).toShort(), move.tiltY)
    }

    @Test
    fun `decode proximity-enter vector`() {
        // Vector: proximity-enter.hex
        // version=1, event_type=0x02, flags=0x04 (HOVER), sequence=0, timestamp_ns=1_000_000_000
        // entering=0x01
        val bytes = loadVector("proximity-enter.hex")
        assertEquals(20, bytes.size, "STYLUS_PROXIMITY frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_PROXIMITY, frame.header.eventType)
        assertEquals(0x04u.toUByte(), frame.header.flags) // HOVER bit set
        assertEquals(0u, frame.header.sequence)
        assertEquals(1_000_000_000uL, frame.header.timestampNs)

        val proximity = assertInstanceOf(StylusEvent.Proximity::class.java, frame.event)
        assertTrue(proximity.entering)
    }

    @Test
    fun `decode proximity-exit vector`() {
        // Vector: proximity-exit.hex
        // version=1, event_type=0x02, flags=0x00 (HOVER clear), sequence=1, timestamp_ns=2_000_000_000
        // entering=0x00
        val bytes = loadVector("proximity-exit.hex")
        assertEquals(20, bytes.size, "STYLUS_PROXIMITY frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_PROXIMITY, frame.header.eventType)
        assertEquals(0x00u.toUByte(), frame.header.flags) // HOVER bit clear
        assertEquals(1u, frame.header.sequence)
        assertEquals(2_000_000_000uL, frame.header.timestampNs)

        val proximity = assertInstanceOf(StylusEvent.Proximity::class.java, frame.event)
        assertFalse(proximity.entering)
    }

    @Test
    fun `decode button-press vector`() {
        // Vector: button-press.hex
        // version=1, event_type=0x03, flags=0x08 (BUTTON_PRIMARY), sequence=2, timestamp_ns=3_000_000_000
        // buttons=0x08 (mirrors bits 3-4 of flags)
        val bytes = loadVector("button-press.hex")
        assertEquals(20, bytes.size, "STYLUS_BUTTON frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_BUTTON, frame.header.eventType)
        assertEquals(0x08u.toUByte(), frame.header.flags) // BUTTON_PRIMARY bit set
        assertEquals(2u, frame.header.sequence)
        assertEquals(3_000_000_000uL, frame.header.timestampNs)

        val button = assertInstanceOf(StylusEvent.Button::class.java, frame.event)
        assertEquals(0x08u.toUByte(), button.buttons)
    }

    // ─────────────────────────────────────────────────────────────
    // Roundtrip tests (encode → decode → assertEquals)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `encode then decode roundtrip for StylusEvent Move`() {
        val event = StylusEvent.Move(x = 0.5f, y = 0.25f, pressure = 49151u, tiltX = 4500, tiltY = -1800)
        val flags: UByte = (Flags.PRESSURE_PRESENT.toUInt() or Flags.TILT_PRESENT.toUInt()).toUByte()

        val encoded = codec.encode(event, flags = flags, sequence = 42u, timestampNs = 8_000_000_000uL)
        assertEquals(36, encoded.size)

        val decoded = codec.decode(encoded)
        val move = assertInstanceOf(StylusEvent.Move::class.java, decoded.event)

        assertEquals(42u, decoded.header.sequence)
        assertEquals(8_000_000_000uL, decoded.header.timestampNs)
        assertEquals(0.5f, move.x, 1e-6f)
        assertEquals(0.25f, move.y, 1e-6f)
        assertEquals(49151u.toUShort(), move.pressure)
        assertEquals(4500.toShort(), move.tiltX)
        assertEquals((-1800).toShort(), move.tiltY)
    }

    @Test
    fun `encode then decode roundtrip for StylusEvent Proximity entering`() {
        val event = StylusEvent.Proximity(entering = true)
        val flags: UByte = Flags.HOVER

        val encoded = codec.encode(event, flags = flags, sequence = 0u, timestampNs = 1_000_000_000uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val proximity = assertInstanceOf(StylusEvent.Proximity::class.java, decoded.event)
        assertTrue(proximity.entering)
    }

    @Test
    fun `encode then decode roundtrip for StylusEvent Proximity leaving`() {
        val event = StylusEvent.Proximity(entering = false)
        val flags: UByte = 0x00u

        val encoded = codec.encode(event, flags = flags, sequence = 1u, timestampNs = 2_000_000_000uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val proximity = assertInstanceOf(StylusEvent.Proximity::class.java, decoded.event)
        assertFalse(proximity.entering)
    }

    @Test
    fun `encode then decode roundtrip for StylusEvent Button`() {
        val event = StylusEvent.Button(buttons = 0x08u)
        val flags: UByte = Flags.BUTTON_PRIMARY

        val encoded = codec.encode(event, flags = flags, sequence = 2u, timestampNs = 3_000_000_000uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val button = assertInstanceOf(StylusEvent.Button::class.java, decoded.event)
        assertEquals(0x08u.toUByte(), button.buttons)
    }

    // ─────────────────────────────────────────────────────────────
    // Encode byte-for-byte equality against test vectors (R10)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `encode STYLUS_MOVE produces byte-for-byte match with move-with-pressure-tilt vector`() {
        val expected = loadVector("move-with-pressure-tilt.hex")
        val event = StylusEvent.Move(x = 0.5f, y = 0.25f, pressure = 49151u, tiltX = 4500, tiltY = -1800)
        val flags: UByte = (Flags.PRESSURE_PRESENT.toUInt() or Flags.TILT_PRESENT.toUInt()).toUByte()

        val actual = codec.encode(event, flags = flags, sequence = 42u, timestampNs = 8_000_000_000uL)
        assertArrayEquals(expected, actual)
    }

    @Test
    fun `encode STYLUS_PROXIMITY entering produces byte-for-byte match with proximity-enter vector`() {
        val expected = loadVector("proximity-enter.hex")
        val event = StylusEvent.Proximity(entering = true)
        val flags: UByte = Flags.HOVER

        val actual = codec.encode(event, flags = flags, sequence = 0u, timestampNs = 1_000_000_000uL)
        assertArrayEquals(expected, actual)
    }

    @Test
    fun `encode STYLUS_PROXIMITY leaving produces byte-for-byte match with proximity-exit vector`() {
        val expected = loadVector("proximity-exit.hex")
        val event = StylusEvent.Proximity(entering = false)
        val flags: UByte = 0x00u

        val actual = codec.encode(event, flags = flags, sequence = 1u, timestampNs = 2_000_000_000uL)
        assertArrayEquals(expected, actual)
    }

    @Test
    fun `encode STYLUS_BUTTON produces byte-for-byte match with button-press vector`() {
        val expected = loadVector("button-press.hex")
        val event = StylusEvent.Button(buttons = 0x08u)
        val flags: UByte = Flags.BUTTON_PRIMARY

        val actual = codec.encode(event, flags = flags, sequence = 2u, timestampNs = 3_000_000_000uL)
        assertArrayEquals(expected, actual)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_SCROLL (R12) — encode, decode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode scroll-down vector matches expected StylusEvent Scroll`() {
        // Vector: scroll-down.hex
        // version=1, event_type=0x04, flags=0x00, sequence=0, timestamp_ns=0
        // delta_x=0, delta_y=30
        val bytes = loadVector("scroll-down.hex")
        assertEquals(20, bytes.size, "STYLUS_SCROLL frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_SCROLL, frame.header.eventType)
        assertEquals(0x00u.toUByte(), frame.header.flags)
        assertEquals(0u, frame.header.sequence)
        assertEquals(0uL, frame.header.timestampNs)

        val scroll = assertInstanceOf(StylusEvent.Scroll::class.java, frame.event)
        assertEquals(0.toShort(), scroll.deltaX)
        assertEquals(30.toShort(), scroll.deltaY)
    }

    @Test
    fun `encode then decode roundtrip for StylusEvent Scroll`() {
        val event = StylusEvent.Scroll(deltaX = 10, deltaY = -20)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 5u, timestampNs = 1_000uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val scroll = assertInstanceOf(StylusEvent.Scroll::class.java, decoded.event)
        assertEquals(10.toShort(), scroll.deltaX)
        assertEquals((-20).toShort(), scroll.deltaY)
        assertEquals(5u, decoded.header.sequence)
    }

    @Test
    fun `encode STYLUS_SCROLL produces byte-for-byte match with scroll-down vector`() {
        val expected = loadVector("scroll-down.hex")
        val event = StylusEvent.Scroll(deltaX = 0, deltaY = 30)

        val actual = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        assertArrayEquals(expected, actual)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_ZOOM (R13) — encode, decode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode zoom-in vector matches expected StylusEvent Zoom`() {
        // Vector: zoom-in.hex
        // version=1, event_type=0x05, flags=0x00, sequence=0, timestamp_ns=0
        // scale_delta=1.10 (f32 LE)
        val bytes = loadVector("zoom-in.hex")
        assertEquals(20, bytes.size, "STYLUS_ZOOM frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(1u.toUByte(), frame.header.version)
        assertEquals(EventType.STYLUS_ZOOM, frame.header.eventType)
        assertEquals(0x00u.toUByte(), frame.header.flags)

        val zoom = assertInstanceOf(StylusEvent.Zoom::class.java, frame.event)
        assertEquals(1.10f, zoom.scaleDelta, 1e-6f)
    }

    @Test
    fun `encode then decode roundtrip for StylusEvent Zoom`() {
        val event = StylusEvent.Zoom(scaleDelta = 1.25f)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 3u, timestampNs = 500uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val zoom = assertInstanceOf(StylusEvent.Zoom::class.java, decoded.event)
        assertEquals(1.25f, zoom.scaleDelta, 1e-6f)
        assertEquals(3u, decoded.header.sequence)
    }

    @Test
    fun `encode STYLUS_ZOOM produces byte-for-byte match with zoom-in vector`() {
        val expected = loadVector("zoom-in.hex")
        val event = StylusEvent.Zoom(scaleDelta = 1.10f)

        val actual = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        assertArrayEquals(expected, actual)
    }

    // ─────────────────────────────────────────────────────────────
    // KEY_EVENT (express keys) — decode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode key-event vector matches expected StylusEvent Key (Cmd+Z tap)`() {
        val bytes = loadVector("key-event.hex")
        assertEquals(20, bytes.size, "KEY_EVENT frame must be 20 bytes")

        val frame = codec.decode(bytes)

        assertEquals(EventType.KEY_EVENT, frame.header.eventType)
        assertEquals(42u, frame.header.sequence)
        assertEquals(12_345uL, frame.header.timestampNs)

        val key = assertInstanceOf(StylusEvent.Key::class.java, frame.event)
        assertEquals(0x06u.toUByte(), key.keyCode)
        assertEquals(KeyModifier.CMD, key.modifiers)
        assertEquals(KeyAction.TAP, key.action)
    }

    @Test
    fun `encode KEY_EVENT produces byte-for-byte match with vector`() {
        val expected = loadVector("key-event.hex")
        val event = StylusEvent.Key(
            keyCode = 0x06u,
            modifiers = KeyModifier.CMD,
            action = KeyAction.TAP,
        )
        val actual = codec.encode(event, flags = 0x00u, sequence = 42u, timestampNs = 12_345uL)
        assertArrayEquals(expected, actual)
    }

    @Test
    fun `encode then decode roundtrip for modifier-only Ctrl press`() {
        val event = StylusEvent.Key(
            keyCode = 0x00u,
            modifiers = KeyModifier.CTRL,
            action = KeyAction.PRESS,
        )
        val encoded = codec.encode(event, flags = 0x00u, sequence = 7u, timestampNs = 1_000uL)
        assertEquals(20, encoded.size)

        val decoded = codec.decode(encoded)
        val key = assertInstanceOf(StylusEvent.Key::class.java, decoded.event)
        assertEquals(0x00u.toUByte(), key.keyCode)
        assertEquals(KeyModifier.CTRL, key.modifiers)
        assertEquals(KeyAction.PRESS, key.action)
    }

    @Test
    fun `decode KEY_EVENT with unknown action byte throws`() {
        // Manually build a frame with action = 0x99.
        val data = ByteArray(20)
        data[0] = 0x01 // version
        data[1] = 0x07 // event_type
        data[16] = 0x06.toByte() // key_code
        data[17] = 0x01.toByte() // modifiers (Cmd)
        data[18] = 0x99.toByte() // unknown action
        org.junit.jupiter.api.assertThrows<ProtocolException> { codec.decode(data) }
    }

    // ─────────────────────────────────────────────────────────────
    // Error / discard tests (R2, R4, R8)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode truncated bytes throws ProtocolException`() {
        // A valid STYLUS_MOVE frame is 36 bytes; feeding 15 (less than header) must throw.
        val truncated = ByteArray(15) { 0x00 }
        truncated[0] = 0x01 // version

        assertThrows<ProtocolException> {
            codec.decode(truncated)
        }
    }

    @Test
    fun `decode unknown event type throws ProtocolException`() {
        // Build a 20-byte frame with event_type = 0xFF (reserved).
        val bytes = ByteArray(20) { 0x00 }
        bytes[0] = 0x01 // version
        bytes[1] = 0xFF.toByte() // unknown event_type

        assertThrows<ProtocolException> {
            codec.decode(bytes)
        }
    }

    @Test
    fun `decode wrong version throws ProtocolException`() {
        // Build a 20-byte frame with version = 0x02 (unknown to this implementation).
        val bytes = ByteArray(20) { 0x00 }
        bytes[0] = 0x02 // unsupported version

        assertThrows<ProtocolException> {
            codec.decode(bytes)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Endianness assertion (R1)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode reads u32 sequence in little-endian order`() {
        // Construct a minimal STYLUS_PROXIMITY frame (20 bytes).
        // Sequence bytes at offset 4: 0x01 0x00 0x00 0x00 → LE value = 1.
        val bytes = ByteArray(20) { 0x00 }
        bytes[0] = 0x01 // version
        bytes[1] = 0x02 // event_type = STYLUS_PROXIMITY
        // flags at [2] = 0x00 (HOVER clear, proximity-exit style so entering=0x00 at [16])
        bytes[4] = 0x01 // sequence LSB = 1 → LE u32 = 1

        val frame = codec.decode(bytes)
        assertEquals(1u, frame.header.sequence, "Sequence must be read as little-endian u32")
    }

    @Test
    fun `decode reads u64 timestamp in little-endian order`() {
        // timestamp_ns at offsets 8–15.
        // 8_000_000_000 = 0x00000001_DCD65000 → LE bytes: 00 50 D6 DC 01 00 00 00
        val bytes = ByteArray(20) { 0x00 }
        bytes[0] = 0x01 // version
        bytes[1] = 0x02 // STYLUS_PROXIMITY
        // Write 8_000_000_000 LE at offset 8
        bytes[8] = 0x00
        bytes[9] = 0x50
        bytes[10] = 0xD6.toByte()
        bytes[11] = 0xDC.toByte()
        bytes[12] = 0x01
        bytes[13] = 0x00
        bytes[14] = 0x00
        bytes[15] = 0x00

        val frame = codec.decode(bytes)
        assertEquals(8_000_000_000uL, frame.header.timestampNs)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_BUTTON consistency check (R8)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode STYLUS_BUTTON with buttons inconsistent with flags throws ProtocolException`() {
        // flags = 0x08 (BUTTON_PRIMARY) but buttons payload byte = 0x00 (inconsistent).
        val bytes = ByteArray(20) { 0x00 }
        bytes[0] = 0x01 // version
        bytes[1] = 0x03 // STYLUS_BUTTON
        bytes[2] = 0x08 // flags: BUTTON_PRIMARY
        // buttons at offset 16 = 0x00 → inconsistent with flags bits 3-4
        bytes[16] = 0x00

        assertThrows<ProtocolException> {
            codec.decode(bytes)
        }
    }

    // ─────────────────────────────────────────────────────────────
    // CURSOR_DELTA — roundtrip + vector (A7 / A13)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `encode then decode roundtrip for StylusEvent CursorDelta`() {
        val event = StylusEvent.CursorDelta(deltaX = 5, deltaY = -3)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 7u, timestampNs = 999uL)
        assertEquals(20, encoded.size, "CURSOR_DELTA frame must be 20 bytes")

        val decoded = codec.decode(encoded)
        val cursorDelta = assertInstanceOf(StylusEvent.CursorDelta::class.java, decoded.event)
        assertEquals(5.toShort(), cursorDelta.deltaX)
        assertEquals((-3).toShort(), cursorDelta.deltaY)
        assertEquals(7u, decoded.header.sequence)
    }

    @Test
    fun `encode CURSOR_DELTA produces byte-for-byte match with cursor-delta vector`() {
        // Vector: version=1, event_type=0x06, flags=0x00, sequence=0, timestamp_ns=0
        // delta_x=10 (i16 LE: 0A 00), delta_y=-5 (i16 LE: FB FF)
        val expected = loadVector("cursor-delta.hex")
        val event = StylusEvent.CursorDelta(deltaX = 10, deltaY = -5)
        val actual = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        assertArrayEquals(
            expected,
            actual,
            "Kotlin encoder must produce byte-for-byte match with cursor-delta.hex vector",
        )
    }

    // ─────────────────────────────────────────────────────────────
    // Extreme values — A7 characterization tests
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `encode Move with x above 1 clamps to 1`() {
        // x=1.5f → clamped to 1.0f on encode (per R6 coerceIn).
        val event = StylusEvent.Move(x = 1.5f, y = 0.5f, pressure = 0u, tiltX = 0, tiltY = 0)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val move = assertInstanceOf(StylusEvent.Move::class.java, decoded.event)
        assertEquals(1.0f, move.x, 1e-6f, "x=1.5f must be clamped to 1.0f before encoding (R6)")
    }

    @Test
    fun `encode Move with x NaN propagates through clamp`() {
        // Kotlin coerceIn with NaN: NaN.coerceIn(0f, 1f) → NaN (JVM behaviour).
        val event = StylusEvent.Move(x = Float.NaN, y = 0.5f, pressure = 0u, tiltX = 0, tiltY = 0)
        // Encoder must not throw.
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val move = assertInstanceOf(StylusEvent.Move::class.java, decoded.event)
        // Lock the observed behaviour: NaN propagates through coerceIn on JVM.
        assertTrue(move.x.isNaN(), "NaN x: JVM coerceIn propagates NaN → decoded x must be NaN")
    }

    @Test
    fun `scroll deltaX Int16 MAX roundtrips`() {
        val event = StylusEvent.Scroll(deltaX = Short.MAX_VALUE, deltaY = 0)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val scroll = assertInstanceOf(StylusEvent.Scroll::class.java, decoded.event)
        assertEquals(Short.MAX_VALUE, scroll.deltaX, "Int16.MAX scroll deltaX must roundtrip")
        assertEquals(0.toShort(), scroll.deltaY)
    }

    @Test
    fun `scroll deltaX Int16 MIN roundtrips`() {
        val event = StylusEvent.Scroll(deltaX = Short.MIN_VALUE, deltaY = 0)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val scroll = assertInstanceOf(StylusEvent.Scroll::class.java, decoded.event)
        assertEquals(Short.MIN_VALUE, scroll.deltaX, "Int16.MIN scroll deltaX must roundtrip")
    }

    @Test
    fun `zoom scaleDelta infinity encodes and decodes`() {
        // Float.POSITIVE_INFINITY encodes as its IEEE 754 bit pattern.
        // The encoder does not validate, so infinity should roundtrip.
        val event = StylusEvent.Zoom(scaleDelta = Float.POSITIVE_INFINITY)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val zoom = assertInstanceOf(StylusEvent.Zoom::class.java, decoded.event)
        assertTrue(
            zoom.scaleDelta.isInfinite() && zoom.scaleDelta > 0,
            "Float.POSITIVE_INFINITY scaleDelta must roundtrip as +infinity",
        )
    }

    @Test
    fun `cursorDelta both deltas at MAX roundtrip`() {
        val event = StylusEvent.CursorDelta(deltaX = Short.MAX_VALUE, deltaY = Short.MAX_VALUE)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val cd = assertInstanceOf(StylusEvent.CursorDelta::class.java, decoded.event)
        assertEquals(Short.MAX_VALUE, cd.deltaX)
        assertEquals(Short.MAX_VALUE, cd.deltaY)
    }

    @Test
    fun `cursorDelta both deltas at MIN roundtrip`() {
        val event = StylusEvent.CursorDelta(deltaX = Short.MIN_VALUE, deltaY = Short.MIN_VALUE)
        val encoded = codec.encode(event, flags = 0x00u, sequence = 0u, timestampNs = 0uL)
        val decoded = codec.decode(encoded)
        val cd = assertInstanceOf(StylusEvent.CursorDelta::class.java, decoded.event)
        assertEquals(Short.MIN_VALUE, cd.deltaX)
        assertEquals(Short.MIN_VALUE, cd.deltaY)
    }

    // ─────────────────────────────────────────────────────────────
    // Forward compatibility (R11)
    // ─────────────────────────────────────────────────────────────

    @Test
    fun `decode ignores trailing bytes beyond known payload size`() {
        // A valid 20-byte STYLUS_PROXIMITY frame with 8 extra bytes appended.
        val valid = loadVector("proximity-enter.hex")
        val withTrailing = valid + ByteArray(8) { 0xFF.toByte() }

        // Must decode successfully and ignore the trailing 8 bytes.
        val frame = codec.decode(withTrailing)
        val proximity = assertInstanceOf(StylusEvent.Proximity::class.java, frame.event)
        assertTrue(proximity.entering)
    }
}
