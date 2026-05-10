import XCTest
@testable import InkBridgeIOS

// MARK: - CaptureResponseParserTests
// H.1 — Test coverage for CaptureResponseParser wire-format parser.

final class CaptureResponseParserTests: XCTestCase {

    // MARK: - H.1a: Valid 4 bytes, not cancelled → .captured with correct fields

    func test_parse_validCaptured_returnsSlotKeyCodeModifiers() {
        // slotId=2, keyCode=0x06 (Z), modifiers=0x08 (CMD), cancelled=0x00
        let data = Data([0x02, 0x06, 0x08, 0x00])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 2, keyCode: 0x06, modifiers: 0x08))
    }

    func test_parse_validCaptured_slotZero() {
        // slotId=0, keyCode=0x01 (S), modifiers=0x0A (CMD|SHIFT), cancelled=0x00
        let data = Data([0x00, 0x01, 0x0A, 0x00])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 0, keyCode: 0x01, modifiers: 0x0A))
    }

    // MARK: - H.1b: Modifiers bitmask preserved exactly

    func test_parse_allModifierBits_preserved() {
        // modifiers = 0x0F (SHIFT|CTRL|ALT|CMD all set)
        let data = Data([0x05, 0x31, 0x0F, 0x00])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 5, keyCode: 0x31, modifiers: 0x0F))
    }

    func test_parse_noModifiers_preserved() {
        // modifiers = 0x00
        let data = Data([0x01, 0x21, 0x00, 0x00])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 1, keyCode: 0x21, modifiers: 0x00))
    }

    // MARK: - H.1c: cancelled=0x01 → .cancelled(slotId), ignores keyCode+modifiers

    func test_parse_cancelled_returnsCancelledWithSlotId() {
        // cancelled=0x01 → keyCode and modifiers are ignored
        let data = Data([0x03, 0xFF, 0xFF, 0x01])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .cancelled(slotId: 3))
    }

    func test_parse_cancelled_slotZero() {
        let data = Data([0x00, 0x00, 0x00, 0x01])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .cancelled(slotId: 0))
    }

    // MARK: - H.1d: Too few bytes → .malformed

    func test_parse_emptyData_returnsMalformed() {
        let result = CaptureResponseParser.parse(Data())
        XCTAssertEqual(result, .malformed)
    }

    func test_parse_threeBytes_returnsMalformed() {
        let result = CaptureResponseParser.parse(Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(result, .malformed)
    }

    func test_parse_oneByteOnly_returnsMalformed() {
        let result = CaptureResponseParser.parse(Data([0xFF]))
        XCTAssertEqual(result, .malformed)
    }

    // MARK: - H.1e: Exactly 4 bytes (boundary) succeeds; 5+ bytes also succeeds (extra ignored)

    func test_parse_exactlyFourBytes_succeeds() {
        let data = Data([0x04, 0x09, 0x02, 0x00])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 4, keyCode: 0x09, modifiers: 0x02))
    }

    func test_parse_moreThanFourBytes_succeeds_extraBytesIgnored() {
        // 8 bytes — only first 4 matter
        let data = Data([0x02, 0x08, 0x04, 0x00, 0xAA, 0xBB, 0xCC, 0xDD])
        let result = CaptureResponseParser.parse(data)
        XCTAssertEqual(result, .captured(slotId: 2, keyCode: 0x08, modifiers: 0x04))
    }
}
