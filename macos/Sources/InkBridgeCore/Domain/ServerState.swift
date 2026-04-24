/// The observable state of the InkBridge macOS server.
///
/// Maps to the macOS connection states defined in transport.md R6.
public enum ServerState: Equatable {
    /// Server is not listening. Either Accessibility permission is not granted
    /// or the server has been explicitly stopped.
    case idle
    /// Server is bound and waiting for a client connection on the given port.
    case listening(port: UInt16)
    /// A transport error occurred. The reason string is suitable for display.
    case degraded(reason: String)
}
