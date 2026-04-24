/// InkBridgeCore — domain, transport, and injection layer.
///
/// Isolated from the SwiftUI app target so that unit tests can import this
/// library without dragging in the `@main` entry point.
///
/// Phase 1+ will add:
///   - BinaryStylusCodec (wire-format encoder/decoder)
///   - UdpListener / TcpListener (NWListener wrappers)
///   - CGEventInjector (CGEventPost tablet events)
///   - AccessibilityGate (AXIsProcessTrusted gating)
public enum InkBridgeCore {
    /// Semantic version string — matches the foundation change tag.
    public static let version: String = "0.0.0-foundation"
}
