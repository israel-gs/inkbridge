import Foundation

/// Stateless, encode-only codec for the InkBridge binary wire protocol v1.
///
/// The iPhone is a send-only client: it never decodes frames from the server
/// through this codec (the CaptureResponseParser handles the 4-byte inline
/// response separately). The decode path present in the macOS server codec is
/// therefore intentionally absent here.
///
/// Ported from `macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift`.
/// Wire format reference: `protocol/README.md`.
///
/// Byte order: little-endian throughout.
/// Header: 16 bytes fixed.
/// Payload sizes:
///   STYLUS_BUTTON    (0x03) → 4 bytes payload → 20 bytes total
///   STYLUS_SCROLL    (0x04) → 4 bytes payload → 20 bytes total
///   STYLUS_ZOOM      (0x05) → 4 bytes payload → 20 bytes total
///   CURSOR_DELTA     (0x06) → 4 bytes payload → 20 bytes total
///   KEY_EVENT        (0x07) → 4 bytes payload → 20 bytes total
///   CAPTURE_REQUEST  (0x08) → 4 bytes payload → 20 bytes total
public struct BinaryStylusCodec {

    public init() {}

    // MARK: - Constants

    private static let protocolVersion: UInt8 = 0x01
    private static let headerSize = 16
    private static let payloadSize = 4

    // Event type byte values (wire protocol §Event types table).
    enum EventType {
        static let stylusButton:   UInt8 = 0x03
        static let stylusScroll:   UInt8 = 0x04
        static let stylusZoom:     UInt8 = 0x05
        static let cursorDelta:    UInt8 = 0x06
        static let keyEvent:       UInt8 = 0x07
        static let captureRequest: UInt8 = 0x08
    }

    // MARK: - Public API

    /// Encodes a ``StylusEvent`` into wire-format `Data` (always 20 bytes for iPhone events).
    ///
    /// - Parameters:
    ///   - event:       The event to encode. Only the 6 iPhone-valid types are supported.
    ///   - flags:       Header flags byte (offset 2). Caller populates BUTTON_PRIMARY /
    ///                  BUTTON_SECONDARY bits for `stylusButton` events (R8).
    ///   - sequence:    Per-session monotonic counter; wraps at 2^32 (R9). Use ``SequenceCounter``.
    ///   - timestampNs: Monotonic nanoseconds from `ProcessInfo.processInfo.systemUptime`
    ///                  converted to ns. Matches Android `System.nanoTime()` semantics.
    /// - Returns: Encoded `Data` (20 bytes).
    @discardableResult
    public static func encode(
        _ event: StylusEvent,
        flags: UInt8,
        sequence: UInt32,
        timestampNs: UInt64
    ) -> Data {
        let eventType: UInt8
        let payloadBytes: [UInt8]

        switch event {
        case let .cursorDelta(dx, dy):
            eventType = EventType.cursorDelta
            payloadBytes = encodeDeltaPayload(a: dx, b: dy)

        case let .stylusButton(buttons, _):
            eventType = EventType.stylusButton
            payloadBytes = [buttons, 0x00, 0x00, 0x00]

        case let .stylusScroll(deltaX, deltaY, _):
            // Truncate Float deltas to Int16 per wire format (i16 LE).
            eventType = EventType.stylusScroll
            payloadBytes = encodeDeltaPayload(a: Int16(deltaX.clamped(-32768...32767)),
                                              b: Int16(deltaY.clamped(-32768...32767)))

        case let .stylusZoom(magnification, _):
            eventType = EventType.stylusZoom
            payloadBytes = encodeFloat32Payload(magnification)

        case let .keyEvent(keyCode, modifiers, action):
            eventType = EventType.keyEvent
            payloadBytes = [keyCode, modifiers, action.rawValue, 0x00]

        case let .captureRequest(slot):
            eventType = EventType.captureRequest
            payloadBytes = [slot, 0x00, 0x00, 0x00]
        }

        var data = Data(capacity: headerSize + payloadSize)
        writeHeader(into: &data, eventType: eventType, flags: flags, sequence: sequence, timestampNs: timestampNs)
        data.append(contentsOf: payloadBytes)
        return data
    }

    // MARK: - Header

    private static func writeHeader(
        into data: inout Data,
        eventType: UInt8,
        flags: UInt8,
        sequence: UInt32,
        timestampNs: UInt64
    ) {
        data.append(protocolVersion) // offset 0: version
        data.append(eventType)       // offset 1: event_type
        data.append(flags)           // offset 2: flags
        data.append(0x00)            // offset 3: _reserved (MUST be 0x00)
        data.appendLE(sequence)      // offset 4–7: sequence u32 LE
        data.appendLE(timestampNs)   // offset 8–15: timestamp_ns u64 LE
    }

    // MARK: - Payload helpers

    /// Encodes two Int16 values as 4 bytes little-endian (used for delta_x / delta_y pairs).
    private static func encodeDeltaPayload(a: Int16, b: Int16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let aLE = a.littleEndian
        let bLE = b.littleEndian
        bytes[0] = UInt8(aLE & 0xFF)
        bytes[1] = UInt8((aLE >> 8) & 0xFF)
        bytes[2] = UInt8(bLE & 0xFF)
        bytes[3] = UInt8((bLE >> 8) & 0xFF)
        return bytes
    }

    /// Encodes a Float as 4 bytes (IEEE 754 bit pattern, little-endian).
    private static func encodeFloat32Payload(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern.littleEndian
        return [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8)  & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
    }
}

// MARK: - Data little-endian write helpers

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}

// MARK: - Float clamping

private extension Float {
    func clamped(_ range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
