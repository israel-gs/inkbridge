import XCTest
@testable import InkBridgeIOS

// MARK: - FakeUDPClient

/// A fake conformer of `UDPClient` used throughout the test suite.
/// Records every `send` call in order; simulates connected or disconnected state.
final class FakeUDPClient: UDPClient, @unchecked Sendable {
    // --- State ---
    var simulatedState: UDPClientState = .idle
    var connectCalled = false
    var disconnectCalled = false
    var sentData: [Data] = []
    var shouldThrowOnSend: (UDPClientError)? = nil

    /// Ordered list of (host, port) pairs from every `connect` call.
    /// Use `.count` to get total connect call count, or inspect values for host verification.
    var sentConnectHosts: [(host: String, port: UInt16)] = []

    /// Queued inbound frames for `receiveMessage`. Add via `enqueueInbound(_:)`.
    var inboundQueue: [Result<Data, UDPClientError>] = []

    // --- Protocol ---
    var state: UDPClientState {
        get async { simulatedState }
    }

    func connect(host: String, port: UInt16) async throws {
        connectCalled = true
        sentConnectHosts.append((host: host, port: port))
        simulatedState = .connected
    }

    func send(_ data: Data) async throws {
        if let err = shouldThrowOnSend { throw err }
        sentData.append(data)
    }

    func disconnect() async {
        disconnectCalled = true
        simulatedState = .idle
    }

    func receiveMessage(timeoutSeconds: TimeInterval = 10) async throws -> Data {
        if inboundQueue.isEmpty {
            throw UDPClientError.timeout
        }
        let result = inboundQueue.removeFirst()
        switch result {
        case .success(let data): return data
        case .failure(let err): throw err
        }
    }

    /// Convenience: queue a successful inbound frame.
    func enqueueInbound(_ data: Data) {
        inboundQueue.append(.success(data))
    }
}

// MARK: - UDPClientTests

final class UDPClientTests: XCTestCase {

    // MARK: C.1 — FakeUDPClient contract: send queues bytes in order

    func test_fakeUDPClient_sendsDataInOrder() async throws {
        let client = FakeUDPClient()
        client.simulatedState = .connected

        let d1 = Data([0x01, 0x02])
        let d2 = Data([0x03, 0x04, 0x05])
        try await client.send(d1)
        try await client.send(d2)

        XCTAssertEqual(client.sentData.count, 2)
        XCTAssertEqual(client.sentData[0], d1)
        XCTAssertEqual(client.sentData[1], d2)
    }

    func test_fakeUDPClient_sendWhileDisconnected_throws() async {
        let client = FakeUDPClient()
        client.simulatedState = .idle
        client.shouldThrowOnSend = .notConnected

        var caught: UDPClientError? = nil
        do {
            try await client.send(Data([0xFF]))
        } catch let err as UDPClientError {
            caught = err
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertEqual(caught, .notConnected)
    }

    func test_fakeUDPClient_initialStateIsIdle() async {
        let client = FakeUDPClient()
        let s = await client.state
        XCTAssertEqual(s, .idle)
    }

    func test_fakeUDPClient_connectTransitionsToConnected() async throws {
        let client = FakeUDPClient()
        try await client.connect(host: "127.0.0.1", port: 4545)
        let s = await client.state
        XCTAssertEqual(s, .connected)
        XCTAssertTrue(client.connectCalled)
    }

    func test_fakeUDPClient_disconnectTransitionsToIdle() async throws {
        let client = FakeUDPClient()
        client.simulatedState = .connected
        await client.disconnect()
        let s = await client.state
        XCTAssertEqual(s, .idle)
        XCTAssertTrue(client.disconnectCalled)
    }

    // MARK: C.1 — UDPClientState equality

    func test_udpClientState_idleEquality() {
        XCTAssertEqual(UDPClientState.idle, .idle)
        XCTAssertNotEqual(UDPClientState.idle, .connecting)
    }

    func test_udpClientState_failedEquality() {
        XCTAssertEqual(UDPClientState.failed(reason: "timeout"), .failed(reason: "timeout"))
        XCTAssertNotEqual(UDPClientState.failed(reason: "timeout"), .failed(reason: "other"))
    }
}
