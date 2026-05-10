import Foundation

// MARK: - CaptureResponseError

/// Errors thrown by `CaptureResponseListener.awaitResponse`.
public enum CaptureResponseError: Error, Equatable {
    /// No response arrived within the timeout window.
    case timeout
    /// The connection was closed before a response was received.
    case connectionClosed
}

// MARK: - CaptureResponseListener

/// Listens for the Mac server's 4-byte capture-response frame after a
/// `CAPTURE_REQUEST` event is sent.
///
/// # Transport decision (Batch 6 H.3)
/// Uses `NWConnection.receiveMessage` on the **same outbound `UDPClient`**
/// connection that sent the `CAPTURE_REQUEST`. UDP is connectionless; the same
/// `NWConnection` that sends outbound frames also receives inbound datagrams
/// from the peer via `receiveMessage(_:)`. This avoids the complexity of opening
/// a second socket / `NWListener`.
///
/// # Fallback note
/// If Block M smoke tests reveal that the Mac server's reply is not delivered
/// via `receiveMessage` on this configuration (e.g. because the connection was
/// initialised with send-only parameters), the fallback is an `NWListener` bound
/// to the same local port. The `CaptureResponseParser` is independent of the
/// transport path and will work with either approach.
///
/// # Concurrency
/// This type is a pure async function wrapper. It is `Sendable` by not holding
/// mutable state beyond the injected `UDPClient` reference (which is already
/// `Sendable`).
public struct CaptureResponseListener: Sendable {

    private let client: any UDPClient

    public init(client: any UDPClient) {
        self.client = client
    }

    /// Waits for the Mac server's 4-byte capture-response and parses it.
    ///
    /// - Parameter timeoutSeconds: How long to wait before giving up.
    ///   Defaults to 10 seconds (per spec §Capture from Mac).
    /// - Returns: A `CaptureResult` describing whether the user captured a key
    ///   combo or cancelled, and which slot it applies to.
    /// - Throws: `CaptureResponseError.timeout` or `.connectionClosed`.
    public func awaitResponse(timeoutSeconds: TimeInterval = 10) async throws -> CaptureResult {
        do {
            let data = try await client.receiveMessage(timeoutSeconds: timeoutSeconds)
            return CaptureResponseParser.parse(data)
        } catch let err as UDPClientError {
            switch err {
            case .timeout:
                throw CaptureResponseError.timeout
            default:
                throw CaptureResponseError.connectionClosed
            }
        } catch {
            throw CaptureResponseError.connectionClosed
        }
    }
}
