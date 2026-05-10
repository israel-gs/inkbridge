import Foundation
import Network

// MARK: - UDPClientState

/// The connection lifecycle state of the UDP transport client.
public enum UDPClientState: Equatable, Sendable {
    /// Not connected; no `NWConnection` exists.
    case idle
    /// A connection attempt is in progress.
    case connecting
    /// The connection is established and ready to send datagrams.
    case connected
    /// The connection has failed. `reason` is a human-readable description.
    case failed(reason: String)
}

// MARK: - UDPClientError

/// Errors thrown by `UDPClient` send and receive operations.
public enum UDPClientError: Error, Equatable, Sendable {
    /// `send` was called while the client is not in the `.connected` state.
    case notConnected
    /// The send operation failed at the Network layer.
    case sendFailed(reason: String)
    /// No inbound frame arrived within the specified timeout.
    case timeout
    /// The connection was closed before a response was received.
    case connectionClosed
}

// MARK: - UDPClient (protocol)

/// A unicast UDP transport used to send encoded binary stylus events to the
/// macOS server. Discovery is handled separately via `BroadcastDiscovery`.
///
/// - Important: Implementations MUST be `Sendable` because they are shared
///   across Swift concurrency task boundaries (capture canvas → send loop).
public protocol UDPClient: Sendable {
    /// Establishes a UDP connection to the given host and port.
    /// Resolves (without throwing) once the underlying transport is ready.
    func connect(host: String, port: UInt16) async throws

    /// Sends `data` as a single UDP datagram.
    /// - Throws: `UDPClientError.notConnected` if not in `.connected` state.
    /// - Throws: `UDPClientError.sendFailed` if the network layer rejects the packet.
    func send(_ data: Data) async throws

    /// Tears down the connection and resets state to `.idle`.
    func disconnect() async

    /// The current lifecycle state. May be read from any async context.
    var state: UDPClientState { get async }

    /// Waits for the next inbound datagram on the established connection.
    ///
    /// Used by `CaptureResponseListener` to receive the Mac server's 4-byte
    /// response after a `CAPTURE_REQUEST` event is sent.
    ///
    /// - Parameter timeoutSeconds: Maximum time to wait before throwing `.timeout`.
    /// - Returns: The raw payload bytes.
    /// - Throws: `UDPClientError.timeout` or `UDPClientError.connectionClosed`.
    func receiveMessage(timeoutSeconds: TimeInterval) async throws -> Data
}
