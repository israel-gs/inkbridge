/// Immutable header present in every InkBridge wire frame (16 bytes).
///
/// Layout (little-endian, all fields contiguous):
///   offset 0  – version     : UInt8
///   offset 1  – eventType   : UInt8
///   offset 2  – flags       : UInt8
///   offset 3  – reserved    : UInt8 (must be 0x00 on send; ignore on receive)
///   offset 4  – sequence    : UInt32 LE
///   offset 8  – timestampNs : UInt64 LE
public struct PacketHeader: Equatable, Sendable {
    public let version: UInt8
    public let eventType: UInt8
    public let flags: UInt8
    public let reserved: UInt8
    public let sequence: UInt32
    public let timestampNs: UInt64

    public init(
        version: UInt8,
        eventType: UInt8,
        flags: UInt8,
        reserved: UInt8,
        sequence: UInt32,
        timestampNs: UInt64
    ) {
        self.version = version
        self.eventType = eventType
        self.flags = flags
        self.reserved = reserved
        self.sequence = sequence
        self.timestampNs = timestampNs
    }
}

/// Flags bitfield constants (offset 2 of the wire header).
/// wire-protocol.md R5.
public enum Flags {
    public static let pressurePresent: UInt8 = 0x01
    public static let tiltPresent: UInt8     = 0x02
    public static let hover: UInt8           = 0x04
    public static let buttonPrimary: UInt8   = 0x08
    public static let buttonSecondary: UInt8 = 0x10
}

/// Event type byte constants (offset 1 of the wire header).
/// wire-protocol.md R4.
public enum EventTypeValue {
    public static let stylusMove: UInt8      = 0x01
    public static let stylusProximity: UInt8 = 0x02
    public static let stylusButton: UInt8    = 0x03
}

/// Structured representation of a stylus event decoded from the wire format.
/// wire-protocol.md R6–R8.
public enum StylusEvent: Equatable, Sendable {

    /// STYLUS_MOVE (event_type = 0x01) — stylus tip touching or hovering with position data.
    /// Payload: 20 bytes. Total frame: 36 bytes.
    ///
    /// - x:        Normalized X position in [0.0, 1.0].
    /// - y:        Normalized Y position in [0.0, 1.0].
    /// - pressure: Raw u16 pressure [0, 65535]. 0 when PRESSURE_PRESENT is clear.
    /// - tiltX:    Tilt around X axis × 100, range [−9000, 9000]. 0 when TILT_PRESENT clear.
    /// - tiltY:    Tilt around Y axis × 100, range [−9000, 9000]. 0 when TILT_PRESENT clear.
    case move(x: Float, y: Float, pressure: UInt16, tiltX: Int16, tiltY: Int16)

    /// STYLUS_PROXIMITY (event_type = 0x02) — stylus entered or left the proximity zone.
    /// Payload: 4 bytes. Total frame: 20 bytes.
    ///
    /// - entering: true = entering proximity (0x01); false = leaving (0x00).
    case proximity(entering: Bool)

    /// STYLUS_BUTTON (event_type = 0x03) — button state changed without movement.
    /// Payload: 4 bytes. Total frame: 20 bytes.
    ///
    /// - buttons: Bitfield mirroring bits 3–4 of the header flags byte.
    case button(buttons: UInt8)
}

/// A successfully decoded wire frame.
public struct DecodedFrame: Equatable, Sendable {
    public let header: PacketHeader
    public let event: StylusEvent

    public init(header: PacketHeader, event: StylusEvent) {
        self.header = header
        self.event = event
    }
}
