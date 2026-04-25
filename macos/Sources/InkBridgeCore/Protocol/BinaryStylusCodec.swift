import Foundation

/// Stateless codec for the InkBridge binary wire protocol v1.
///
/// Encodes ``StylusEvent`` instances to `Data` and decodes `Data` back to ``DecodedFrame``.
/// Zero external dependencies — uses only raw byte manipulation via `Data` subscripting.
///
/// Wire format reference: openspec/changes/foundation/specs/wire-protocol.md R1–R13.
///
/// Byte order: little-endian throughout (R1).
/// Header: 16 bytes fixed (R3).
/// Payload sizes:
///   STYLUS_MOVE      (0x01) → 20 bytes payload → 36 bytes total (R6)
///   STYLUS_PROXIMITY (0x02) → 4 bytes payload  → 20 bytes total (R7)
///   STYLUS_BUTTON    (0x03) → 4 bytes payload  → 20 bytes total (R8)
///   STYLUS_SCROLL    (0x04) → 4 bytes payload  → 20 bytes total (R12)
///   STYLUS_ZOOM      (0x05) → 4 bytes payload  → 20 bytes total (R13)
public struct BinaryStylusCodec {

    public init() {}

    private static let protocolVersion: UInt8 = 0x01
    private static let headerSize = 16
    private static let movePayloadSize = 20
    private static let proxButtonPayloadSize = 4
    private static let scrollZoomPayloadSize = 4

    // ─────────────────────────────────────────────────────────────
    // Encode
    // ─────────────────────────────────────────────────────────────

    /// Encodes a ``StylusEvent`` into wire-format `Data`.
    ///
    /// - Parameters:
    ///   - event:       The stylus event to encode.
    ///   - flags:       The flags byte (header offset 2). Caller sets PRESSURE_PRESENT,
    ///                  TILT_PRESENT, HOVER, BUTTON_PRIMARY, BUTTON_SECONDARY bits (R5).
    ///   - sequence:    Per-session monotonic counter; wraps at 2^32 (R9).
    ///   - timestampNs: Monotonic nanoseconds from Android `System.nanoTime()` (R3).
    /// - Returns: Encoded `Data` (36 bytes for MOVE, 20 bytes for PROXIMITY/BUTTON).
    /// - Throws: ``ProtocolError`` — currently this encoder never throws, but the
    ///           signature is `throws` for symmetry with `decode` and future validation.
    public static func encode(
        _ event: StylusEvent,
        flags: UInt8,
        sequence: UInt32,
        timestampNs: UInt64
    ) throws -> Data {
        let eventType: UInt8
        let payloadSize: Int
        let payloadWriter: (inout Data) -> Void

        switch event {
        case let .move(x, y, pressure, tiltX, tiltY):
            eventType = EventTypeValue.stylusMove
            payloadSize = movePayloadSize
            payloadWriter = { data in
                writeMovePayload(into: &data, x: x, y: y, pressure: pressure, tiltX: tiltX, tiltY: tiltY)
            }
        case let .proximity(entering):
            eventType = EventTypeValue.stylusProximity
            payloadSize = proxButtonPayloadSize
            payloadWriter = { data in
                writeProximityPayload(into: &data, entering: entering)
            }
        case let .button(buttons):
            eventType = EventTypeValue.stylusButton
            payloadSize = proxButtonPayloadSize
            payloadWriter = { data in
                writeButtonPayload(into: &data, buttons: buttons)
            }
        case let .scroll(deltaX, deltaY):
            eventType = EventTypeValue.stylusScroll
            payloadSize = scrollZoomPayloadSize
            payloadWriter = { data in
                writeScrollPayload(into: &data, deltaX: deltaX, deltaY: deltaY)
            }
        case let .zoom(scaleDelta):
            eventType = EventTypeValue.stylusZoom
            payloadSize = scrollZoomPayloadSize
            payloadWriter = { data in
                writeZoomPayload(into: &data, scaleDelta: scaleDelta)
            }
        case let .cursorDelta(deltaX, deltaY):
            eventType = EventTypeValue.cursorDelta
            payloadSize = scrollZoomPayloadSize
            payloadWriter = { data in
                writeScrollPayload(into: &data, deltaX: deltaX, deltaY: deltaY)
            }
        case let .key(keyCode, modifiers, action):
            eventType = EventTypeValue.keyEvent
            payloadSize = scrollZoomPayloadSize
            payloadWriter = { data in
                writeKeyPayload(into: &data, keyCode: keyCode, modifiers: modifiers, action: action)
            }
        }

        var data = Data(capacity: headerSize + payloadSize)
        writeHeader(into: &data, eventType: eventType, flags: flags, sequence: sequence, timestampNs: timestampNs)
        payloadWriter(&data)
        return data
    }

    // MARK: - Header writer

    private static func writeHeader(
        into data: inout Data,
        eventType: UInt8,
        flags: UInt8,
        sequence: UInt32,
        timestampNs: UInt64
    ) {
        data.append(protocolVersion)          // offset 0: version
        data.append(eventType)                // offset 1: event_type
        data.append(flags)                    // offset 2: flags
        data.append(0x00)                     // offset 3: _reserved (MUST be 0x00)
        data.appendLE(sequence)               // offset 4–7: sequence u32 LE
        data.appendLE(timestampNs)            // offset 8–15: timestamp_ns u64 LE
    }

    // MARK: - Payload writers

    private static func writeMovePayload(
        into data: inout Data,
        x: Float, y: Float,
        pressure: UInt16,
        tiltX: Int16, tiltY: Int16
    ) {
        // Clamp x and y to [0.0, 1.0] per R6 before encoding.
        data.appendLE(x.clamped(to: 0.0...1.0))  // offset 16–19: x f32 LE
        data.appendLE(y.clamped(to: 0.0...1.0))  // offset 20–23: y f32 LE
        data.appendLE(pressure)                   // offset 24–25: pressure u16 LE
        data.appendLE(tiltX)                      // offset 26–27: tilt_x i16 LE
        data.appendLE(tiltY)                      // offset 28–29: tilt_y i16 LE
        data.appendLE(UInt16(0))                  // offset 30–31: _pad = 0x0000
        data.appendLE(UInt32(0))                  // offset 32–35: _reserved = 0x00000000
    }

    private static func writeProximityPayload(into data: inout Data, entering: Bool) {
        data.append(entering ? 0x01 : 0x00)  // offset 16: entering
        data.append(0x00)                    // offset 17: _pad[0]
        data.append(0x00)                    // offset 18: _pad[1]
        data.append(0x00)                    // offset 19: _pad[2]
    }

    private static func writeButtonPayload(into data: inout Data, buttons: UInt8) {
        data.append(buttons)  // offset 16: buttons
        data.append(0x00)     // offset 17: _pad[0]
        data.append(0x00)     // offset 18: _pad[1]
        data.append(0x00)     // offset 19: _pad[2]
    }

    private static func writeScrollPayload(into data: inout Data, deltaX: Int16, deltaY: Int16) {
        data.appendLE(deltaX)   // offset 16–17: delta_x i16 LE
        data.appendLE(deltaY)   // offset 18–19: delta_y i16 LE
    }

    private static func writeZoomPayload(into data: inout Data, scaleDelta: Float) {
        data.appendLE(scaleDelta)  // offset 16–19: scale_delta f32 LE
    }

    private static func writeKeyPayload(
        into data: inout Data,
        keyCode: UInt8,
        modifiers: UInt8,
        action: KeyAction
    ) {
        data.append(keyCode)            // offset 16: key_code
        data.append(modifiers)          // offset 17: modifiers
        data.append(action.rawValue)    // offset 18: action
        data.append(0x00)               // offset 19: _pad
    }

    // ─────────────────────────────────────────────────────────────
    // Decode
    // ─────────────────────────────────────────────────────────────

    /// Decodes wire-format `Data` into a ``DecodedFrame``.
    ///
    /// Forward-compatible per R11: trailing bytes beyond the known payload size are silently ignored.
    ///
    /// - Throws: ``ProtocolError/truncated`` if the data is shorter than the header.
    /// - Throws: ``ProtocolError/badVersion(got:)`` if the version byte ≠ 0x01 (R2).
    /// - Throws: ``ProtocolError/unknownType(got:)`` if the event_type is not 0x01–0x03 (R4).
    /// - Throws: ``ProtocolError/truncated`` if the data is shorter than the expected frame size.
    /// - Throws: ``ProtocolError/buttonsInconsistentWithFlags`` for R8 violations.
    public static func decode(_ data: Data) throws -> DecodedFrame {
        guard data.count >= headerSize else {
            throw ProtocolError.truncated
        }

        var cursor = data.startIndex

        let version = data.read(UInt8.self, at: &cursor)
        guard version == protocolVersion else {
            throw ProtocolError.badVersion(got: version)
        }

        let eventType  = data.read(UInt8.self, at: &cursor)
        let flags      = data.read(UInt8.self, at: &cursor)
        let reserved   = data.read(UInt8.self, at: &cursor)
        let sequence   = data.readLE(UInt32.self, at: &cursor)
        let timestampNs = data.readLE(UInt64.self, at: &cursor)

        let header = PacketHeader(
            version: version,
            eventType: eventType,
            flags: flags,
            reserved: reserved,
            sequence: sequence,
            timestampNs: timestampNs
        )

        let event: StylusEvent
        switch eventType {
        case EventTypeValue.stylusMove:
            event = try decodeMovePayload(data: data, cursor: &cursor)
        case EventTypeValue.stylusProximity:
            event = try decodeProximityPayload(data: data, cursor: &cursor)
        case EventTypeValue.stylusButton:
            event = try decodeButtonPayload(data: data, cursor: &cursor, flags: flags)
        case EventTypeValue.stylusScroll:
            event = try decodeScrollPayload(data: data, cursor: &cursor)
        case EventTypeValue.stylusZoom:
            event = try decodeZoomPayload(data: data, cursor: &cursor)
        case EventTypeValue.cursorDelta:
            event = try decodeCursorDeltaPayload(data: data, cursor: &cursor)
        case EventTypeValue.keyEvent:
            event = try decodeKeyPayload(data: data, cursor: &cursor)
        default:
            throw ProtocolError.unknownType(got: eventType)
        }

        return DecodedFrame(header: header, event: event)
    }

    // MARK: - Payload decoders

    private static func decodeMovePayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + movePayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let x        = data.readLE(Float.self, at: &cursor)
        let y        = data.readLE(Float.self, at: &cursor)
        let pressure = data.readLE(UInt16.self, at: &cursor)
        let tiltX    = data.readLE(Int16.self, at: &cursor)
        let tiltY    = data.readLE(Int16.self, at: &cursor)
        // _pad (2 bytes) and _reserved (4 bytes) are consumed and discarded per R6.
        // Bytes beyond offset 36 are not read (R11 — forward compatibility).
        return .move(x: x, y: y, pressure: pressure, tiltX: tiltX, tiltY: tiltY)
    }

    private static func decodeProximityPayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + proxButtonPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let entering = data.read(UInt8.self, at: &cursor) != 0
        // _pad 3 bytes are consumed and discarded.
        return .proximity(entering: entering)
    }

    private static func decodeButtonPayload(
        data: Data,
        cursor: inout Data.Index,
        flags: UInt8
    ) throws -> StylusEvent {
        let required = headerSize + proxButtonPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let buttons = data.read(UInt8.self, at: &cursor)
        // _pad 3 bytes consumed and discarded.

        // R8: buttons payload must mirror bits 3–4 of the header flags byte (mask 0x18).
        let flagsBits34 = flags & 0x18
        guard buttons == flagsBits34 else {
            throw ProtocolError.buttonsInconsistentWithFlags(buttons: buttons, flagsBits34: flagsBits34)
        }
        return .button(buttons: buttons)
    }

    private static func decodeScrollPayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + scrollZoomPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let deltaX = data.readLE(Int16.self, at: &cursor)   // offset 16–17: delta_x i16 LE
        let deltaY = data.readLE(Int16.self, at: &cursor)   // offset 18–19: delta_y i16 LE
        return .scroll(deltaX: deltaX, deltaY: deltaY)
    }

    private static func decodeZoomPayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + scrollZoomPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let scaleDelta = data.readLE(Float.self, at: &cursor)  // offset 16–19: scale_delta f32 LE
        return .zoom(scaleDelta: scaleDelta)
    }

    private static func decodeCursorDeltaPayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + scrollZoomPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let deltaX = data.readLE(Int16.self, at: &cursor)
        let deltaY = data.readLE(Int16.self, at: &cursor)
        return .cursorDelta(deltaX: deltaX, deltaY: deltaY)
    }

    private static func decodeKeyPayload(data: Data, cursor: inout Data.Index) throws -> StylusEvent {
        let required = headerSize + scrollZoomPayloadSize
        guard data.count >= required else { throw ProtocolError.truncated }

        let keyCode   = data.read(UInt8.self, at: &cursor)
        let modifiers = data.read(UInt8.self, at: &cursor)
        let actionRaw = data.read(UInt8.self, at: &cursor)
        // _pad consumed and discarded.
        _ = data.read(UInt8.self, at: &cursor)

        guard let action = KeyAction(rawValue: actionRaw) else {
            throw ProtocolError.unknownType(got: actionRaw)
        }
        return .key(keyCode: keyCode, modifiers: modifiers, action: action)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Data extensions for little-endian byte I/O
// These helpers replace Foundation struct-packing shortcuts with explicit byte
// manipulation, matching the "no dependency shortcuts" requirement.
// ─────────────────────────────────────────────────────────────────────────────

private extension Data {

    // MARK: Write helpers

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: Float) {
        // IEEE 754 float encoded as its bit pattern in little-endian u32.
        appendLE(value.bitPattern)
    }

    // MARK: Read helpers

    /// Reads a single byte at `cursor` and advances `cursor` by 1.
    func read(_ type: UInt8.Type, at cursor: inout Index) -> UInt8 {
        let byte = self[cursor]
        cursor = index(after: cursor)
        return byte
    }

    /// Reads a little-endian fixed-width integer at `cursor` and advances `cursor`.
    func readLE<T: FixedWidthInteger>(_ type: T.Type, at cursor: inout Index) -> T {
        let size = MemoryLayout<T>.size
        let end = index(cursor, offsetBy: size)
        let value = self[cursor..<end].withUnsafeBytes { ptr in
            ptr.loadUnaligned(as: T.self)
        }
        cursor = end
        return T(littleEndian: value)
    }

    /// Reads an IEEE 754 float (little-endian u32 bit pattern) at `cursor`.
    func readLE(_ type: Float.Type, at cursor: inout Index) -> Float {
        let bits = readLE(UInt32.self, at: &cursor)
        return Float(bitPattern: bits)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
