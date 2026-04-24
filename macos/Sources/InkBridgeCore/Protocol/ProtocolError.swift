/// Errors thrown by ``BinaryStylusCodec`` when the input data violates the
/// InkBridge wire protocol v1 contract (wire-protocol.md R2, R4, R8).
public enum ProtocolError: Error, Equatable {
    /// The data is shorter than the required minimum (header or payload).
    case truncated
    /// The version byte at offset 0 is not 0x01 (wire-protocol.md R2).
    case badVersion(got: UInt8)
    /// The event_type byte at offset 1 is not 0x01, 0x02, or 0x03 (R4).
    case unknownType(got: UInt8)
    /// STYLUS_BUTTON: the buttons payload byte is inconsistent with flags bits 3–4 (R8).
    case buttonsInconsistentWithFlags(buttons: UInt8, flagsBits34: UInt8)
}
