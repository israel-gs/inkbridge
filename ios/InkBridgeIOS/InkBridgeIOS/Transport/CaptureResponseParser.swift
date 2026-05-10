import Foundation

// MARK: - CaptureResult

/// The result of parsing a 4-byte capture-response frame from the Mac server.
///
/// Wire format (4 bytes, little-endian):
/// ```
/// [0] slotId     : u8   — Express Key slot index (0-5)
/// [1] keyCode    : u8   — macOS virtual key code
/// [2] modifiers  : u8   — bitmask: SHIFT=1, CTRL=2, ALT=4, CMD=8
/// [3] cancelled  : u8   — 0x01 = user cancelled; 0x00 = captured successfully
/// ```
/// When `cancelled == 0x01`, `keyCode` and `modifiers` fields are ignored.
public enum CaptureResult: Equatable {
    /// The user pressed a key combo on the Mac; the slot should be assigned this mapping.
    case captured(slotId: UInt8, keyCode: UInt8, modifiers: UInt8)
    /// The user cancelled the capture on the Mac side. No assignment is made.
    case cancelled(slotId: UInt8)
    /// The response frame was not exactly 4 bytes and cannot be parsed.
    case malformed
}

// MARK: - CaptureResponseParser

/// Inline parser for the 4-byte capture-response frame sent from the Mac server.
///
/// This parser is intentionally separate from `BinaryStylusCodec` — the codec
/// handles outbound encoding of stylus events, whereas the capture response is
/// inbound metadata with a different wire format.
///
/// # Relationship to NWConnection decision
/// The parser is pure-data and has no dependency on the transport layer.
/// The transport (see `CaptureResponseListener`) decides whether to use
/// `NWConnection.receiveMessage` or `NWListener` to receive the raw bytes;
/// this parser only cares about the `Data` payload.
public enum CaptureResponseParser {

    /// Parses a raw 4-byte capture-response frame.
    ///
    /// - Parameter data: The raw bytes received from the Mac server.
    /// - Returns: `.captured`, `.cancelled`, or `.malformed`.
    public static func parse(_ data: Data) -> CaptureResult {
        guard data.count >= 4 else { return .malformed }

        let bytes = [UInt8](data)
        let slotId    = bytes[0]
        let keyCode   = bytes[1]
        let modifiers = bytes[2]
        let cancelled = bytes[3]

        if cancelled == 0x01 {
            return .cancelled(slotId: slotId)
        } else {
            return .captured(slotId: slotId, keyCode: keyCode, modifiers: modifiers)
        }
    }
}
