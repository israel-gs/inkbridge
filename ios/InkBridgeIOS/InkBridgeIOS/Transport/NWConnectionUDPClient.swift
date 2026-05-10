import Foundation
import Network

// MARK: - Continuation bridge helper

/// Thread-safe container for a `CheckedContinuation` that ensures exactly-once resumption.
/// Used to bridge NWConnection's callback-based state updates into async/await.
final class ConnectContinuationBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    func store(_ c: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        continuation = c
    }

    func resumeOnce(with result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard let c = continuation else { return }
        continuation = nil
        switch result {
        case .success: c.resume()
        case .failure(let e): c.resume(throwing: e)
        }
    }
}

// MARK: - NWConnectionUDPClient

/// A `UDPClient` implementation backed by `NWConnection` with `NWParameters.udp`.
///
/// Used exclusively for the **unicast data path** — sending encoded binary events
/// to a known Mac server IP. Broadcast sends are handled separately via
/// `BSDSocketBroadcastDiscovery` (NWConnection rejects broadcast on iOS).
///
/// Thread safety: `actor` isolation.
///
/// Reconnect backoff (spec §Reconnection): 0.5 / 1 / 2 / 5 s, capped at 5 s.
public actor NWConnectionUDPClient: UDPClient {

    // MARK: - State

    private var connection: NWConnection?
    private var _state: UDPClientState = .idle
    private var backoff = BackoffPolicy()

    // MARK: - UDPClient conformance

    public var state: UDPClientState { _state }

    public init() {}

    /// Establishes a UDP connection to `host:port`.
    ///
    /// Tears down any existing connection first. Resolves once the
    /// `NWConnection` reports `.ready` or throws on permanent failure.
    public func connect(host: String, port: UInt16) async throws {
        teardown()
        _state = .connecting
        backoff.reset()

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )
        self.connection = conn

        let box = ConnectContinuationBox()

        conn.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task {
                await self.applyConnectionState(newState, box: box)
            }
        }
        conn.start(queue: .global(qos: .userInteractive))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.store(continuation)
        }
    }

    public func send(_ data: Data) async throws {
        guard _state == .connected, let conn = connection else {
            throw UDPClientError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: UDPClientError.sendFailed(reason: error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func disconnect() async {
        teardown()
        _state = .idle
    }

    /// Receives the next inbound datagram on the existing outbound connection.
    ///
    /// # NWConnection.receiveMessage decision (Batch 6 H.3)
    /// Design.md §Risks item 7 deferred the choice between:
    /// - (A) `NWConnection.receiveMessage` on the same TX connection — simpler, no extra port.
    /// - (B) `NWListener` on the same local port — requires binding a new listener socket.
    ///
    /// **Decision: (A) `NWConnection.receiveMessage`.**
    /// UDP is connectionless; the same `NWConnection` that sends also receives datagrams
    /// from the peer. Apple's Network framework delivers inbound frames via `receive(_:)` /
    /// `receiveMessage(_:)` on an established UDP NWConnection. This is the simpler path.
    /// If the Mac server smoke tests (Block M) reveal that inbound delivery is unreliable
    /// on this configuration (e.g. the connection was started with a specific send-only
    /// parameter), the fallback is an `NWListener` on the same local port — implement then.
    ///
    /// The 10-second timeout is enforced via `Task.sleep` racing against the receive callback.
    public func receiveMessage(timeoutSeconds: TimeInterval = 10) async throws -> Data {
        guard _state == .connected, let conn = connection else {
            throw UDPClientError.notConnected
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            // Race: receive vs. timeout
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    conn.receiveMessage { content, _, isComplete, error in
                        if let error {
                            continuation.resume(throwing: UDPClientError.connectionClosed)
                            return
                        }
                        guard let content else {
                            continuation.resume(throwing: UDPClientError.connectionClosed)
                            return
                        }
                        continuation.resume(returning: content)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw UDPClientError.timeout
            }

            // Return whichever task finishes first, cancel the other.
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private

    private func teardown() {
        connection?.cancel()
        connection = nil
    }

    private func applyConnectionState(_ newState: NWConnection.State, box: ConnectContinuationBox) {
        switch newState {
        case .ready:
            _state = .connected
            box.resumeOnce(with: .success(()))
        case .failed(let error):
            _state = .failed(reason: error.localizedDescription)
            box.resumeOnce(with: .failure(UDPClientError.sendFailed(reason: error.localizedDescription)))
        case .cancelled:
            if _state != .idle {
                _state = .idle
            }
        default:
            break
        }
    }
}
