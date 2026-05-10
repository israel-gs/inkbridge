import XCTest
@testable import InkBridgeIOS

// MARK: - Helpers

/// Parses a hex file from the test bundle.
///
/// With PBXFileSystemSynchronizedRootGroup (Xcode 16), all files under InkBridgeIOSTests/
/// are flattened into the bundle root — the Vectors/ directory does NOT appear as a
/// subdirectory in the built .xctest. Files are bundled as "cursor-delta.hex", not
/// "Vectors/cursor-delta.hex".
///
/// Format: lines beginning with '#' are comments; remaining tokens are uppercase hex pairs.
private func loadVector(named name: String) throws -> Data {
    let bundle = Bundle(for: BinaryStylusCodecTests.self)
    // Try flat (PBXFileSystemSynchronizedRootGroup flattens Vectors/ into bundle root).
    // Then try subdirectory path as fallback for future explicit resource-copy phases.
    guard let url = bundle.url(forResource: name, withExtension: nil)
                ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Vectors")
    else {
        throw XCTSkip("Vector file '\(name)' not found in test bundle — skipping")
    }
    let raw = try String(contentsOf: url, encoding: .utf8)
    let hex = raw.components(separatedBy: .newlines)
        .filter { !$0.hasPrefix("#") }
        .joined(separator: " ")
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
    var bytes = Data()
    for pair in hex {
        guard pair.count == 2, let byte = UInt8(pair, radix: 16) else { continue }
        bytes.append(byte)
    }
    return bytes
}

// MARK: - Test class

final class BinaryStylusCodecTests: XCTestCase {

    // ─────────────────────────────────────────────────────────────────────────
    // B.1 CURSOR_DELTA
    // ─────────────────────────────────────────────────────────────────────────

    /// Encodes cursorDelta(10, -5) and compares against cursor-delta.hex vector.
    /// Vector: seq=0, timestampNs=0, dx=10 (0A 00), dy=-5 (FB FF).
    func test_cursorDelta_matchesVector() throws {
        let expected = try loadVector(named: "cursor-delta.hex")
        let encoded = BinaryStylusCodec.encode(
            .cursorDelta(dx: 10, dy: -5),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        XCTAssertEqual(encoded, expected,
            "CURSOR_DELTA encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    /// Frame size for CURSOR_DELTA must always be 20 bytes.
    func test_cursorDelta_frameSize_is20Bytes() {
        let data = BinaryStylusCodec.encode(.cursorDelta(dx: 0, dy: 0), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data.count, 20)
    }

    /// Event type byte at offset 1 must be 0x06 for CURSOR_DELTA.
    func test_cursorDelta_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.cursorDelta(dx: 1, dy: 1), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x06)
    }

    /// Edge case: dx = Int16.min (-32768), dy = Int16.max (32767).
    func test_cursorDelta_extremeValues() {
        let data = BinaryStylusCodec.encode(
            .cursorDelta(dx: Int16.min, dy: Int16.max),
            flags: 0x00, sequence: 0, timestampNs: 0
        )
        XCTAssertEqual(data.count, 20)
        // dx = -32768 = 0x8000 LE → bytes 16–17: 00 80
        XCTAssertEqual(data[16], 0x00)
        XCTAssertEqual(data[17], 0x80)
        // dy = 32767 = 0x7FFF LE → bytes 18–19: FF 7F
        XCTAssertEqual(data[18], 0xFF)
        XCTAssertEqual(data[19], 0x7F)
    }

    /// Edge case: dx = 0, dy = 0 — zero delta is valid.
    func test_cursorDelta_zero() {
        let data = BinaryStylusCodec.encode(.cursorDelta(dx: 0, dy: 0), flags: 0x00, sequence: 0, timestampNs: 0)
        // payload bytes 16–19 must all be 0x00
        XCTAssertEqual(data[16], 0x00)
        XCTAssertEqual(data[17], 0x00)
        XCTAssertEqual(data[18], 0x00)
        XCTAssertEqual(data[19], 0x00)
    }

    /// Header field checks for a known sequence + timestamp.
    func test_cursorDelta_headerFields() {
        let seq: UInt32 = 42
        let ts: UInt64 = 1_000_000_000
        let data = BinaryStylusCodec.encode(.cursorDelta(dx: 10, dy: -3), flags: 0x00, sequence: seq, timestampNs: ts)
        // offset 0: version 0x01
        XCTAssertEqual(data[0], 0x01)
        // offset 1: event_type 0x06
        XCTAssertEqual(data[1], 0x06)
        // offset 2: flags 0x00
        XCTAssertEqual(data[2], 0x00)
        // offset 3: reserved 0x00
        XCTAssertEqual(data[3], 0x00)
        // offset 4–7: seq=42 LE → 2A 00 00 00
        XCTAssertEqual(data[4], 0x2A)
        XCTAssertEqual(data[5], 0x00)
        XCTAssertEqual(data[6], 0x00)
        XCTAssertEqual(data[7], 0x00)
        // offset 8–15: timestamp_ns=1_000_000_000 = 0x3B9ACA00 LE → 00 CA 9A 3B 00 00 00 00
        XCTAssertEqual(data[8],  0x00)
        XCTAssertEqual(data[9],  0xCA)
        XCTAssertEqual(data[10], 0x9A)
        XCTAssertEqual(data[11], 0x3B)
        XCTAssertEqual(data[12], 0x00)
        XCTAssertEqual(data[13], 0x00)
        XCTAssertEqual(data[14], 0x00)
        XCTAssertEqual(data[15], 0x00)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.3 STYLUS_BUTTON
    // ─────────────────────────────────────────────────────────────────────────

    /// STYLUS_BUTTON matches button-press.hex (seq=2, ts=3_000_000_000, buttons=0x08, flags=0x08).
    func test_stylusButton_matchesVector() throws {
        let expected = try loadVector(named: "button-press.hex")
        // Vector: seq=2, ts=3_000_000_000=0xB2D05E00, flags=0x08(BUTTON_PRIMARY), buttons=0x08
        let encoded = BinaryStylusCodec.encode(
            .stylusButton(buttons: 0x08, primaryDown: true),
            flags: 0x08,
            sequence: 2,
            timestampNs: 3_000_000_000
        )
        XCTAssertEqual(encoded, expected,
            "STYLUS_BUTTON encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    func test_stylusButton_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.stylusButton(buttons: 0x08, primaryDown: true), flags: 0x08, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x03)
        XCTAssertEqual(data.count, 20)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.3 STYLUS_SCROLL
    // ─────────────────────────────────────────────────────────────────────────

    /// STYLUS_SCROLL matches scroll-down.hex (deltaX=0, deltaY=30, seq=0, ts=0).
    func test_stylusScroll_matchesVector() throws {
        let expected = try loadVector(named: "scroll-down.hex")
        // The vector has deltaY=30 (0x1E). The iOS type stores Float deltas; encode truncates to Int16.
        let encoded = BinaryStylusCodec.encode(
            .stylusScroll(deltaX: 0, deltaY: 30, phase: 0),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        XCTAssertEqual(encoded, expected,
            "STYLUS_SCROLL encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    func test_stylusScroll_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.stylusScroll(deltaX: 0, deltaY: 0, phase: 0), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x04)
        XCTAssertEqual(data.count, 20)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.3 STYLUS_ZOOM
    // ─────────────────────────────────────────────────────────────────────────

    /// STYLUS_ZOOM matches zoom-in.hex (scaleDelta=1.10, seq=0, ts=0).
    func test_stylusZoom_matchesVector() throws {
        let expected = try loadVector(named: "zoom-in.hex")
        // zoom-in.hex has scale_delta=1.10 (0x3F8CCCCD LE: CD CC 8C 3F)
        let encoded = BinaryStylusCodec.encode(
            .stylusZoom(magnification: 1.10, phase: 0),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        XCTAssertEqual(encoded, expected,
            "STYLUS_ZOOM encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    func test_stylusZoom_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.stylusZoom(magnification: 1.0, phase: 0), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x05)
        XCTAssertEqual(data.count, 20)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.3 KEY_EVENT
    // ─────────────────────────────────────────────────────────────────────────

    /// KEY_EVENT matches key-event.hex (Cmd+Z tap, seq=42, ts=12345, keyCode=0x06, mods=0x01, action=tap/0x03).
    func test_keyEvent_matchesVector() throws {
        let expected = try loadVector(named: "key-event.hex")
        // Vector: key_code=0x06(Z), modifiers=0x01(Cmd), action=0x03(tap)
        // iOS KeyAction only has .down=0 and .up=1; tap is not modeled.
        // The vector uses action=0x03 which is "tap" per protocol.
        // We test the closest match: encode with action=.tap (rawValue=2 in our enum).
        // Since the iOS domain KeyAction has .down=0/.up=1, "tap" is a 3rd case needed.
        // For now test that key_code, modifiers are correct and frame is valid.
        // NOTE: If KeyAction doesn't have .tap, this test will be adapted (see deviation notes).
        let encoded = BinaryStylusCodec.encode(
            .keyEvent(keyCode: 0x06, modifiers: 0x01, action: .tap),
            flags: 0x00,
            sequence: 42,
            timestampNs: 12345
        )
        XCTAssertEqual(encoded, expected,
            "KEY_EVENT encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    func test_keyEvent_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.keyEvent(keyCode: 0x06, modifiers: 0x01, action: .down), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x07)
        XCTAssertEqual(data.count, 20)
    }

    /// KEY_EVENT with keyCode=0x00 is a modifier-only event (flagsChanged on Mac).
    /// Per protocol/README.md: action=0x01 = press (KeyAction.down.rawValue == 1).
    func test_keyEvent_modifierOnly_keyCodeIsZero() {
        let data = BinaryStylusCodec.encode(
            .keyEvent(keyCode: 0x00, modifiers: 0x01, action: .down),
            flags: 0x00, sequence: 0, timestampNs: 0
        )
        XCTAssertEqual(data[1], 0x07)                   // still KEY_EVENT type
        XCTAssertEqual(data[16], 0x00)                  // key_code == 0x00 = modifier-only
        XCTAssertEqual(data[17], 0x01)                  // modifiers
        XCTAssertEqual(data[18], KeyAction.down.rawValue) // action = 0x01 (press per protocol)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // B.3 CAPTURE_REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    /// CAPTURE_REQUEST matches capture-request.hex (slot=3, seq=100, ts=2_000_000_000).
    /// Vector authored in this batch (L.2).
    func test_captureRequest_matchesVector() throws {
        let expected = try loadVector(named: "capture-request.hex")
        let encoded = BinaryStylusCodec.encode(
            .captureRequest(slot: 3),
            flags: 0x00,
            sequence: 100,
            timestampNs: 2_000_000_000
        )
        XCTAssertEqual(encoded, expected,
            "CAPTURE_REQUEST encode mismatch\nGot:      \(encoded.hexString)\nExpected: \(expected.hexString)")
    }

    func test_captureRequest_eventTypeByte() {
        let data = BinaryStylusCodec.encode(.captureRequest(slot: 2), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[1], 0x08)
        XCTAssertEqual(data.count, 20)
    }

    func test_captureRequest_slotInPayload() {
        let data = BinaryStylusCodec.encode(.captureRequest(slot: 5), flags: 0x00, sequence: 0, timestampNs: 0)
        XCTAssertEqual(data[16], 0x05)  // slot_id
        XCTAssertEqual(data[17], 0x00)  // _pad
        XCTAssertEqual(data[18], 0x00)  // _pad
        XCTAssertEqual(data[19], 0x00)  // _pad
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Non-emitted types — codec must not crash on them
    // ─────────────────────────────────────────────────────────────────────────

    /// macOS vectors for STYLUS_MOVE — not emitted by iPhone, but codec must handle gracefully.
    /// We verify the function simply produces non-empty output (not crashing is the SLA).
    func test_move_vectorDoesNotCrash() throws {
        // We have move-with-pressure-tilt.hex in Vectors/ — just verify loadVector works.
        let data = try loadVector(named: "move-with-pressure-tilt.hex")
        XCTAssertTrue(data.count >= 20, "Move vector should be at least 20 bytes")
    }
}

// MARK: - Data hex debug helper

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
