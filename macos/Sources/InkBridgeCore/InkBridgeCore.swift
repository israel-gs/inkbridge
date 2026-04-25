/// InkBridgeCore — domain, transport, and injection layer.
///
/// Isolated from the SwiftUI app target so that unit tests can import this
/// library without dragging in the `@main` entry point.
///
/// Implemented modules:
///   - ``BinaryStylusCodec`` — wire-format encoder/decoder (wire-protocol.md v1)
///   - ``UDPListener`` / ``TCPListener`` — NWListener wrappers
///   - ``CGEventInjector`` — CGEventPost tablet and gesture events
///   - ``InkBridgeServer`` — frame routing and accessibility gating
public enum InkBridgeCore {
    /// Semantic version string — matches the foundation change tag.
    public static let version: String = "0.0.0-foundation"
}
