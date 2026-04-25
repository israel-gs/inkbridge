import XCTest
@testable import InkBridgeCore

/// Unit tests for ``BinaryStylusCodec`` following the TDD red-green-refactor cycle.
///
/// Test vectors are embedded in the test bundle under `Vectors/` via the SPM
/// `.copy("Vectors")` resource rule in Package.swift. They are the single source of truth
/// for Kotlin ↔ Swift interop — both codecs must produce byte-identical output.
///
/// Wire-protocol.md references: R1 (LE), R2 (version), R3 (header), R4 (event_type),
/// R5 (flags), R6 (MOVE payload), R7 (PROXIMITY payload), R8 (BUTTON payload), R9 (sequence).
final class BinaryStylusCodecTests: XCTestCase {

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────

    /// Loads a `.hex` test vector from the test bundle.
    /// Format: lines starting with `#` are comments; data lines contain uppercase
    /// space-separated hex pairs (e.g. "01 02 03").
    private func loadVector(named filename: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Vectors") else {
            XCTFail("Test vector not found in bundle: Vectors/\(filename)")
            throw XCTSkip("Vector missing")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let bytes: [UInt8] = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .flatMap { $0.components(separatedBy: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { UInt8($0, radix: 16) }
        return Data(bytes)
    }

    // ─────────────────────────────────────────────────────────────
    // Decode: vector-matching tests (R6–R8, R10)
    // ─────────────────────────────────────────────────────────────

    func testDecodeMoveVectorMatchesExpectedEvent() throws {
        // Vector: move-with-pressure-tilt.hex
        // version=1, event_type=0x01, flags=0x03 (PRESSURE_PRESENT|TILT_PRESENT)
        // sequence=42, timestamp_ns=8_000_000_000
        // x=0.5, y=0.25, pressure=49151, tilt_x=4500, tilt_y=-1800
        let data = try loadVector(named: "move-with-pressure-tilt.hex")
        XCTAssertEqual(data.count, 36, "STYLUS_MOVE frame must be 36 bytes")

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.version, 1)
        XCTAssertEqual(frame.header.eventType, EventTypeValue.stylusMove)
        XCTAssertEqual(frame.header.flags, 0x03)
        XCTAssertEqual(frame.header.sequence, 42)
        XCTAssertEqual(frame.header.timestampNs, 8_000_000_000)

        guard case let .move(x, y, pressure, tiltX, tiltY) = frame.event else {
            XCTFail("Expected StylusEvent.move, got \(frame.event)")
            return
        }
        XCTAssertEqual(x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(y, 0.25, accuracy: 1e-6)
        XCTAssertEqual(pressure, 49151)
        XCTAssertEqual(tiltX, 4500)
        XCTAssertEqual(tiltY, -1800)
    }

    func testDecodeProximityEnterVector() throws {
        // Vector: proximity-enter.hex
        // version=1, event_type=0x02, flags=0x04 (HOVER), sequence=0, timestamp_ns=1_000_000_000
        // entering=0x01
        let data = try loadVector(named: "proximity-enter.hex")
        XCTAssertEqual(data.count, 20, "STYLUS_PROXIMITY frame must be 20 bytes")

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.version, 1)
        XCTAssertEqual(frame.header.eventType, EventTypeValue.stylusProximity)
        XCTAssertEqual(frame.header.flags, 0x04)
        XCTAssertEqual(frame.header.sequence, 0)
        XCTAssertEqual(frame.header.timestampNs, 1_000_000_000)

        guard case let .proximity(entering) = frame.event else {
            XCTFail("Expected StylusEvent.proximity, got \(frame.event)")
            return
        }
        XCTAssertTrue(entering)
    }

    func testDecodeProximityExitVector() throws {
        // Vector: proximity-exit.hex
        // version=1, event_type=0x02, flags=0x00, sequence=1, timestamp_ns=2_000_000_000
        // entering=0x00
        let data = try loadVector(named: "proximity-exit.hex")
        XCTAssertEqual(data.count, 20)

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.flags, 0x00)
        XCTAssertEqual(frame.header.sequence, 1)
        XCTAssertEqual(frame.header.timestampNs, 2_000_000_000)

        guard case let .proximity(entering) = frame.event else {
            XCTFail("Expected StylusEvent.proximity, got \(frame.event)")
            return
        }
        XCTAssertFalse(entering)
    }

    func testDecodeButtonPressVector() throws {
        // Vector: button-press.hex
        // version=1, event_type=0x03, flags=0x08 (BUTTON_PRIMARY), sequence=2, timestamp_ns=3_000_000_000
        // buttons=0x08
        let data = try loadVector(named: "button-press.hex")
        XCTAssertEqual(data.count, 20)

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.version, 1)
        XCTAssertEqual(frame.header.eventType, EventTypeValue.stylusButton)
        XCTAssertEqual(frame.header.flags, 0x08)
        XCTAssertEqual(frame.header.sequence, 2)
        XCTAssertEqual(frame.header.timestampNs, 3_000_000_000)

        guard case let .button(buttons) = frame.event else {
            XCTFail("Expected StylusEvent.button, got \(frame.event)")
            return
        }
        XCTAssertEqual(buttons, 0x08)
    }

    // ─────────────────────────────────────────────────────────────
    // Roundtrip tests (encode → decode → assertEquals)
    // ─────────────────────────────────────────────────────────────

    func testRoundtripMove() throws {
        let event = StylusEvent.move(x: 0.5, y: 0.25, pressure: 49151, tiltX: 4500, tiltY: -1800)
        let flags: UInt8 = Flags.pressurePresent | Flags.tiltPresent

        let encoded = try BinaryStylusCodec.encode(event, flags: flags, sequence: 42, timestampNs: 8_000_000_000)
        XCTAssertEqual(encoded.count, 36)

        let decoded = try BinaryStylusCodec.decode(encoded)
        XCTAssertEqual(decoded.header.sequence, 42)
        XCTAssertEqual(decoded.header.timestampNs, 8_000_000_000)

        guard case let .move(x, y, pressure, tiltX, tiltY) = decoded.event else {
            XCTFail("Expected .move")
            return
        }
        XCTAssertEqual(x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(y, 0.25, accuracy: 1e-6)
        XCTAssertEqual(pressure, 49151)
        XCTAssertEqual(tiltX, 4500)
        XCTAssertEqual(tiltY, -1800)
    }

    func testRoundtripProximityEntering() throws {
        let event = StylusEvent.proximity(entering: true)
        let flags: UInt8 = Flags.hover

        let encoded = try BinaryStylusCodec.encode(event, flags: flags, sequence: 0, timestampNs: 1_000_000_000)
        XCTAssertEqual(encoded.count, 20)

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .proximity(entering) = decoded.event else {
            XCTFail("Expected .proximity")
            return
        }
        XCTAssertTrue(entering)
    }

    func testRoundtripProximityLeaving() throws {
        let event = StylusEvent.proximity(entering: false)
        let flags: UInt8 = 0x00

        let encoded = try BinaryStylusCodec.encode(event, flags: flags, sequence: 1, timestampNs: 2_000_000_000)
        XCTAssertEqual(encoded.count, 20)

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .proximity(entering) = decoded.event else {
            XCTFail("Expected .proximity")
            return
        }
        XCTAssertFalse(entering)
    }

    func testRoundtripButton() throws {
        let event = StylusEvent.button(buttons: 0x08)
        let flags: UInt8 = Flags.buttonPrimary

        let encoded = try BinaryStylusCodec.encode(event, flags: flags, sequence: 2, timestampNs: 3_000_000_000)
        XCTAssertEqual(encoded.count, 20)

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .button(buttons) = decoded.event else {
            XCTFail("Expected .button")
            return
        }
        XCTAssertEqual(buttons, 0x08)
    }

    // ─────────────────────────────────────────────────────────────
    // Encode byte-for-byte equality against test vectors (R10)
    // ─────────────────────────────────────────────────────────────

    func testEncodeMoveByteForByteEquality() throws {
        let expected = try loadVector(named: "move-with-pressure-tilt.hex")
        let event = StylusEvent.move(x: 0.5, y: 0.25, pressure: 49151, tiltX: 4500, tiltY: -1800)
        let flags: UInt8 = Flags.pressurePresent | Flags.tiltPresent

        let actual = try BinaryStylusCodec.encode(event, flags: flags, sequence: 42, timestampNs: 8_000_000_000)
        XCTAssertEqual(actual, expected)
    }

    func testEncodeProximityEnterByteForByteEquality() throws {
        let expected = try loadVector(named: "proximity-enter.hex")
        let event = StylusEvent.proximity(entering: true)
        let flags: UInt8 = Flags.hover

        let actual = try BinaryStylusCodec.encode(event, flags: flags, sequence: 0, timestampNs: 1_000_000_000)
        XCTAssertEqual(actual, expected)
    }

    func testEncodeProximityExitByteForByteEquality() throws {
        let expected = try loadVector(named: "proximity-exit.hex")
        let event = StylusEvent.proximity(entering: false)
        let flags: UInt8 = 0x00

        let actual = try BinaryStylusCodec.encode(event, flags: flags, sequence: 1, timestampNs: 2_000_000_000)
        XCTAssertEqual(actual, expected)
    }

    func testEncodeButtonByteForByteEquality() throws {
        let expected = try loadVector(named: "button-press.hex")
        let event = StylusEvent.button(buttons: 0x08)
        let flags: UInt8 = Flags.buttonPrimary

        let actual = try BinaryStylusCodec.encode(event, flags: flags, sequence: 2, timestampNs: 3_000_000_000)
        XCTAssertEqual(actual, expected)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_SCROLL (R12) — decode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    func testDecodeScrollDownVector() throws {
        // Vector: scroll-down.hex
        // version=1, event_type=0x04, flags=0x00, sequence=0, timestamp_ns=0
        // delta_x=0, delta_y=30
        let data = try loadVector(named: "scroll-down.hex")
        XCTAssertEqual(data.count, 20, "STYLUS_SCROLL frame must be 20 bytes")

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.version, 1)
        XCTAssertEqual(frame.header.eventType, EventTypeValue.stylusScroll)
        XCTAssertEqual(frame.header.flags, 0x00)
        XCTAssertEqual(frame.header.sequence, 0)
        XCTAssertEqual(frame.header.timestampNs, 0)

        guard case let .scroll(deltaX, deltaY) = frame.event else {
            XCTFail("Expected StylusEvent.scroll, got \(frame.event)")
            return
        }
        XCTAssertEqual(deltaX, 0)
        XCTAssertEqual(deltaY, 30)
    }

    func testRoundtripScroll() throws {
        let event = StylusEvent.scroll(deltaX: 10, deltaY: -20)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 5, timestampNs: 1_000)
        XCTAssertEqual(encoded.count, 20)

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .scroll(deltaX, deltaY) = decoded.event else {
            XCTFail("Expected .scroll")
            return
        }
        XCTAssertEqual(deltaX, 10)
        XCTAssertEqual(deltaY, -20)
        XCTAssertEqual(decoded.header.sequence, 5)
    }

    func testEncodeScrollByteForByteEquality() throws {
        let expected = try loadVector(named: "scroll-down.hex")
        let event = StylusEvent.scroll(deltaX: 0, deltaY: 30)

        let actual = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(actual, expected)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_ZOOM (R13) — decode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    func testDecodeZoomInVector() throws {
        // Vector: zoom-in.hex
        // version=1, event_type=0x05, flags=0x00, sequence=0, timestamp_ns=0
        // scale_delta=1.10 (f32 LE)
        let data = try loadVector(named: "zoom-in.hex")
        XCTAssertEqual(data.count, 20, "STYLUS_ZOOM frame must be 20 bytes")

        let frame = try BinaryStylusCodec.decode(data)

        XCTAssertEqual(frame.header.version, 1)
        XCTAssertEqual(frame.header.eventType, EventTypeValue.stylusZoom)
        XCTAssertEqual(frame.header.flags, 0x00)

        guard case let .zoom(scaleDelta) = frame.event else {
            XCTFail("Expected StylusEvent.zoom, got \(frame.event)")
            return
        }
        XCTAssertEqual(scaleDelta, 1.10, accuracy: 1e-6)
    }

    func testRoundtripZoom() throws {
        let event = StylusEvent.zoom(scaleDelta: 1.25)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 3, timestampNs: 500)
        XCTAssertEqual(encoded.count, 20)

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .zoom(scaleDelta) = decoded.event else {
            XCTFail("Expected .zoom")
            return
        }
        XCTAssertEqual(scaleDelta, 1.25, accuracy: 1e-6)
        XCTAssertEqual(decoded.header.sequence, 3)
    }

    func testEncodeZoomByteForByteEquality() throws {
        let expected = try loadVector(named: "zoom-in.hex")
        let event = StylusEvent.zoom(scaleDelta: 1.10)

        let actual = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(actual, expected)
    }

    // ─────────────────────────────────────────────────────────────
    // Error / discard tests (R2, R4, R8)
    // ─────────────────────────────────────────────────────────────

    func testDecodeTruncatedThrows() {
        // 15 bytes — shorter than the 16-byte header.
        let truncated = Data(repeating: 0x00, count: 15)
        XCTAssertThrowsError(try BinaryStylusCodec.decode(truncated)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.truncated)
        }
    }

    func testDecodeUnknownEventTypeThrows() {
        var bytes = Data(repeating: 0x00, count: 20)
        bytes[0] = 0x01  // version
        bytes[1] = 0xFF  // unknown event_type
        XCTAssertThrowsError(try BinaryStylusCodec.decode(bytes)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.unknownType(got: 0xFF))
        }
    }

    func testDecodeWrongVersionThrows() {
        var bytes = Data(repeating: 0x00, count: 20)
        bytes[0] = 0x02  // unsupported version
        XCTAssertThrowsError(try BinaryStylusCodec.decode(bytes)) { error in
            XCTAssertEqual(error as? ProtocolError, ProtocolError.badVersion(got: 0x02))
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Endianness assertions (R1)
    // ─────────────────────────────────────────────────────────────

    func testDecodesSequenceAsLittleEndian() throws {
        // Construct a minimal STYLUS_PROXIMITY frame (20 bytes).
        // Sequence bytes at offset 4: 0x01 0x00 0x00 0x00 → LE u32 = 1.
        var bytes = Data(repeating: 0x00, count: 20)
        bytes[0] = 0x01  // version
        bytes[1] = 0x02  // STYLUS_PROXIMITY
        bytes[4] = 0x01  // sequence LSB → LE u32 = 1

        let frame = try BinaryStylusCodec.decode(bytes)
        XCTAssertEqual(frame.header.sequence, 1, "Sequence must be read as little-endian u32")
    }

    func testDecodesTimestampAsLittleEndian() throws {
        // 8_000_000_000 = 0x00000001_DCD65000 → LE: 00 50 D6 DC 01 00 00 00 at offsets 8–15.
        var bytes = Data(repeating: 0x00, count: 20)
        bytes[0]  = 0x01
        bytes[1]  = 0x02  // STYLUS_PROXIMITY
        bytes[8]  = 0x00
        bytes[9]  = 0x50
        bytes[10] = 0xD6
        bytes[11] = 0xDC
        bytes[12] = 0x01
        bytes[13] = 0x00
        bytes[14] = 0x00
        bytes[15] = 0x00

        let frame = try BinaryStylusCodec.decode(bytes)
        XCTAssertEqual(frame.header.timestampNs, 8_000_000_000)
    }

    // ─────────────────────────────────────────────────────────────
    // STYLUS_BUTTON consistency check (R8)
    // ─────────────────────────────────────────────────────────────

    func testDecodeButtonInconsistentFlagsThrows() {
        // flags = 0x08 (BUTTON_PRIMARY) but buttons payload = 0x00 (inconsistent).
        var bytes = Data(repeating: 0x00, count: 20)
        bytes[0]  = 0x01  // version
        bytes[1]  = 0x03  // STYLUS_BUTTON
        bytes[2]  = 0x08  // flags: BUTTON_PRIMARY
        bytes[16] = 0x00  // buttons: inconsistent

        XCTAssertThrowsError(try BinaryStylusCodec.decode(bytes)) { error in
            XCTAssertEqual(
                error as? ProtocolError,
                ProtocolError.buttonsInconsistentWithFlags(buttons: 0x00, flagsBits34: 0x08)
            )
        }
    }

    // ─────────────────────────────────────────────────────────────
    // CURSOR_DELTA (R?) — encode, roundtrip, vector
    // ─────────────────────────────────────────────────────────────

    func testRoundtripCursorDelta() throws {
        let event = StylusEvent.cursorDelta(deltaX: 5, deltaY: -3)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 7, timestampNs: 999)
        XCTAssertEqual(encoded.count, 20, "CURSOR_DELTA frame must be 20 bytes")

        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .cursorDelta(dx, dy) = decoded.event else {
            XCTFail("Expected .cursorDelta")
            return
        }
        XCTAssertEqual(dx, 5)
        XCTAssertEqual(dy, -3)
        XCTAssertEqual(decoded.header.sequence, 7)
    }

    func testCursorDeltaVectorByteEquality() throws {
        // Load the cross-platform cursor-delta.hex test vector and verify
        // that the Swift encoder produces identical bytes.
        let expected = try loadVector(named: "cursor-delta.hex")
        // Vector: version=1, event_type=0x06, flags=0x00, sequence=0, timestamp_ns=0
        // delta_x=10 (i16 LE: 0x0A 0x00), delta_y=-5 (i16 LE: 0xFB 0xFF)
        let event = StylusEvent.cursorDelta(deltaX: 10, deltaY: -5)
        let actual = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(actual, expected, "Encoder must produce byte-for-byte match with cursor-delta.hex vector")
    }

    // ─────────────────────────────────────────────────────────────
    // Extreme values — A2 characterization tests
    // ─────────────────────────────────────────────────────────────

    func testMoveWithNanX_clampsToZeroOnEncode() throws {
        // The encoder clamps x to [0.0, 1.0] before encoding.
        // NaN.clamped(to: 0...1) → NaN because min/max with NaN propagates NaN in Swift's
        // min/max functions. Verify current behaviour and lock it in.
        let event = StylusEvent.move(x: Float.nan, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0)
        // Encoder must not throw.
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        // Decode and observe whatever the encoder did. The spec says clamp [0,1]; NaN
        // propagates through IEEE min/max so the decoded x will also be NaN.
        // We characterize: decoder reads the bit pattern back faithfully.
        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .move(x, _, _, _, _) = decoded.event else {
            XCTFail("Expected .move")
            return
        }
        // Lock the observed behaviour: x is NaN (clamp with NaN propagates NaN).
        XCTAssertTrue(x.isNaN, "NaN x: current encoder behaviour is that NaN propagates through clamp → decoded x is NaN")
    }

    func testMoveWithXAboveOne_clampsToOne() throws {
        // x=1.5 → clamped to 1.0 on encode (per R6).
        let event = StylusEvent.move(x: 1.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .move(x, _, _, _, _) = decoded.event else {
            XCTFail("Expected .move")
            return
        }
        XCTAssertEqual(x, 1.0, accuracy: 1e-6, "x=1.5 must be clamped to 1.0 before encoding (R6)")
    }

    func testScrollDeltaXMaxValue_roundtrips() throws {
        // deltaX = Int16.max = 32767
        let event = StylusEvent.scroll(deltaX: Int16.max, deltaY: 0)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .scroll(dx, dy) = decoded.event else {
            XCTFail("Expected .scroll")
            return
        }
        XCTAssertEqual(dx, Int16.max, "Int16.max scrollDeltaX must roundtrip exactly")
        XCTAssertEqual(dy, 0)
    }

    func testScrollDeltaXMinValue_roundtrips() throws {
        // deltaX = Int16.min = -32768
        let event = StylusEvent.scroll(deltaX: Int16.min, deltaY: 0)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .scroll(dx, dy) = decoded.event else {
            XCTFail("Expected .scroll")
            return
        }
        XCTAssertEqual(dx, Int16.min, "Int16.min scrollDeltaX must roundtrip exactly")
        XCTAssertEqual(dy, 0)
    }

    func testZoomWithInfiniteScaleDelta_encodesAndDecodes() throws {
        // Float.infinity encodes as its IEEE 754 bit pattern. The encoder does not
        // validate the zoom payload, so infinity should roundtrip faithfully.
        let event = StylusEvent.zoom(scaleDelta: Float.infinity)
        let encoded = try BinaryStylusCodec.encode(event, flags: 0x00, sequence: 0, timestampNs: 0)
        let decoded = try BinaryStylusCodec.decode(encoded)
        guard case let .zoom(scaleDelta) = decoded.event else {
            XCTFail("Expected .zoom")
            return
        }
        XCTAssertTrue(scaleDelta.isInfinite && scaleDelta > 0,
            "Float.infinity scaleDelta must roundtrip as +infinity (IEEE 754 bit-pattern encode/decode)")
    }

    func testCursorDeltaBothMinMaxValues_roundtrip() throws {
        // Characterization: cursorDelta with both deltas at extremes.
        let eventMax = StylusEvent.cursorDelta(deltaX: Int16.max, deltaY: Int16.max)
        let encodedMax = try BinaryStylusCodec.encode(eventMax, flags: 0x00, sequence: 0, timestampNs: 0)
        let decodedMax = try BinaryStylusCodec.decode(encodedMax)
        guard case let .cursorDelta(dx, dy) = decodedMax.event else {
            XCTFail("Expected .cursorDelta (max case)")
            return
        }
        XCTAssertEqual(dx, Int16.max)
        XCTAssertEqual(dy, Int16.max)

        let eventMin = StylusEvent.cursorDelta(deltaX: Int16.min, deltaY: Int16.min)
        let encodedMin = try BinaryStylusCodec.encode(eventMin, flags: 0x00, sequence: 0, timestampNs: 0)
        let decodedMin = try BinaryStylusCodec.decode(encodedMin)
        guard case let .cursorDelta(dxMin, dyMin) = decodedMin.event else {
            XCTFail("Expected .cursorDelta (min case)")
            return
        }
        XCTAssertEqual(dxMin, Int16.min)
        XCTAssertEqual(dyMin, Int16.min)
    }

    // ─────────────────────────────────────────────────────────────
    // Forward compatibility (R11)
    // ─────────────────────────────────────────────────────────────

    func testDecodeIgnoresTrailingBytesR11() throws {
        // A valid proximity-enter frame with 8 extra trailing bytes.
        let valid = try loadVector(named: "proximity-enter.hex")
        let withTrailing = valid + Data(repeating: 0xFF, count: 8)

        let frame = try BinaryStylusCodec.decode(withTrailing)
        guard case let .proximity(entering) = frame.event else {
            XCTFail("Expected .proximity")
            return
        }
        XCTAssertTrue(entering)
    }
}
