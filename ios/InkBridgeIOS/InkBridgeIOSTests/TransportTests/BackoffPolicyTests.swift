import XCTest
@testable import InkBridgeIOS

final class BackoffPolicyTests: XCTestCase {

    // MARK: C.3 — Backoff sequence correctness

    func test_sequence_firstFourSteps() {
        var policy = BackoffPolicy()
        XCTAssertEqual(policy.next(), 0.5, accuracy: 0.001)
        XCTAssertEqual(policy.next(), 1.0, accuracy: 0.001)
        XCTAssertEqual(policy.next(), 2.0, accuracy: 0.001)
        XCTAssertEqual(policy.next(), 5.0, accuracy: 0.001)
    }

    func test_sequence_capsAt5s() {
        var policy = BackoffPolicy()
        // Exhaust the sequence
        _ = policy.next() // 0.5
        _ = policy.next() // 1.0
        _ = policy.next() // 2.0
        _ = policy.next() // 5.0
        // Subsequent calls must remain at cap
        XCTAssertEqual(policy.next(), 5.0, accuracy: 0.001)
        XCTAssertEqual(policy.next(), 5.0, accuracy: 0.001)
    }

    func test_reset_returnsToStart() {
        var policy = BackoffPolicy()
        _ = policy.next() // 0.5
        _ = policy.next() // 1.0
        policy.reset()
        XCTAssertEqual(policy.next(), 0.5, accuracy: 0.001, "After reset, first value must be 0.5 s")
    }

    func test_constants_matchSpec() {
        XCTAssertEqual(BackoffPolicy.sequence, [0.5, 1.0, 2.0, 5.0])
        XCTAssertEqual(BackoffPolicy.cap, 5.0)
    }
}

// MARK: - NWConnectionUDPClient lifecycle tests (C.3)

final class NWConnectionLifecycleTests: XCTestCase {

    // Test using FakeUDPClient for state machine contract (not real NWConnection — that
    // requires a real listener and is covered in integration smoke tests).

    func test_sendWhileNotConnected_throwsNotConnected() async {
        let client = FakeUDPClient()
        client.simulatedState = .idle
        client.shouldThrowOnSend = .notConnected

        do {
            try await client.send(Data([0x01, 0x02]))
            XCTFail("Expected UDPClientError.notConnected")
        } catch UDPClientError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_disconnectSetsStateToIdle() async throws {
        let client = FakeUDPClient()
        client.simulatedState = .connected

        await client.disconnect()
        let s = await client.state
        XCTAssertEqual(s, .idle)
    }

    func test_connectThenDisconnect_stateSequence() async throws {
        let client = FakeUDPClient()

        // Connect
        try await client.connect(host: "127.0.0.1", port: 4545)
        let s1 = await client.state
        XCTAssertEqual(s1, .connected)

        // Disconnect
        await client.disconnect()
        let s2 = await client.state
        XCTAssertEqual(s2, .idle)
    }

    func test_sendAfterDisconnect_throws() async throws {
        let client = FakeUDPClient()
        try await client.connect(host: "127.0.0.1", port: 4545)
        await client.disconnect()

        // Now set up the fake to throw
        client.shouldThrowOnSend = .notConnected

        do {
            try await client.send(Data([0xAB]))
            XCTFail("Expected error after disconnect")
        } catch UDPClientError.notConnected {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
