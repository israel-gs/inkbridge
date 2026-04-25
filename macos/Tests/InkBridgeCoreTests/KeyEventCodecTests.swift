import XCTest
@testable import InkBridgeCore

final class KeyEventCodecTests: XCTestCase {

    func test_encodeKeyTapRoundTrip() throws {
        let event: StylusEvent = .key(keyCode: 0x06, modifiers: 0x01, action: .tap) // Cmd+Z
        let data = try BinaryStylusCodec.encode(
            event,
            flags: 0,
            sequence: 42,
            timestampNs: 12_345
        )
        XCTAssertEqual(data.count, 20)

        let frame = try BinaryStylusCodec.decode(data)
        XCTAssertEqual(frame.header.eventType, 0x07)
        XCTAssertEqual(frame.header.sequence, 42)
        XCTAssertEqual(frame.event, event)
    }

    func test_encodeModifierHoldRoundTrip() throws {
        let press: StylusEvent   = .key(keyCode: 0x00, modifiers: 0x02, action: .press)
        let release: StylusEvent = .key(keyCode: 0x00, modifiers: 0x02, action: .release)

        let pressData   = try BinaryStylusCodec.encode(press,   flags: 0, sequence: 1, timestampNs: 0)
        let releaseData = try BinaryStylusCodec.encode(release, flags: 0, sequence: 2, timestampNs: 0)

        XCTAssertEqual(try BinaryStylusCodec.decode(pressData).event, press)
        XCTAssertEqual(try BinaryStylusCodec.decode(releaseData).event, release)
    }

    func test_unknownActionByteThrowsUnknownType() throws {
        // Build a 20-byte frame manually with action = 0x99.
        var data = Data()
        data.append(0x01)                          // version
        data.append(0x07)                          // event_type = KEY_EVENT
        data.append(0x00)                          // flags
        data.append(0x00)                          // _reserved
        data.append(contentsOf: [0, 0, 0, 0])      // sequence
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // timestamp
        data.append(0x06)                          // key_code
        data.append(0x01)                          // modifiers
        data.append(0x99)                          // unknown action
        data.append(0x00)                          // _pad

        XCTAssertThrowsError(try BinaryStylusCodec.decode(data)) { error in
            guard let pe = error as? ProtocolError, case .unknownType(let got) = pe else {
                return XCTFail("Expected unknownType, got \(error)")
            }
            XCTAssertEqual(got, 0x99)
        }
    }

    func test_canonicalVectorRoundTrip() throws {
        // Loads protocol/test-vectors/key-event.hex (mirrored into the test
        // bundle) and confirms encode + decode agree byte-for-byte.
        guard let url = Bundle.module.url(forResource: "key-event", withExtension: "hex", subdirectory: "Vectors") else {
            return XCTFail("Vector key-event.hex not found in test bundle")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let hex = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty })!
        let bytes = hex
            .split(separator: " ")
            .map { UInt8($0, radix: 16)! }
        let data = Data(bytes)

        let frame = try BinaryStylusCodec.decode(data)
        XCTAssertEqual(frame.header.eventType, 0x07)
        XCTAssertEqual(frame.header.sequence, 42)
        XCTAssertEqual(frame.header.timestampNs, 12_345)
        XCTAssertEqual(frame.event, .key(keyCode: 0x06, modifiers: 0x01, action: .tap))

        let reEncoded = try BinaryStylusCodec.encode(
            frame.event,
            flags: frame.header.flags,
            sequence: frame.header.sequence,
            timestampNs: frame.header.timestampNs
        )
        XCTAssertEqual(reEncoded, data)
    }

    func test_truncatedKeyFrameThrows() throws {
        // 18 bytes — header + 2 bytes of payload (need 4).
        var data = Data()
        data.append(0x01)
        data.append(0x07)
        data.append(0x00)
        data.append(0x00)
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        data.append(0x06)
        data.append(0x01)

        XCTAssertThrowsError(try BinaryStylusCodec.decode(data))
    }
}
