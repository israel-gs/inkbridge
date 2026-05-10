import XCTest
@testable import InkBridgeIOS

// MARK: - FakeBroadcastDiscovery

/// A `BroadcastDiscovery` conformer for unit testing. Emits hosts pushed into it
/// via `emit(_:)`. Used by ConnectionViewModel tests and discovery flow tests.
final class FakeBroadcastDiscovery: BroadcastDiscovery, @unchecked Sendable {
    private var continuation: AsyncStream<DiscoveredHost>.Continuation?
    private(set) var startCalled = false
    private(set) var stopCalled = false

    lazy var hosts: AsyncStream<DiscoveredHost> = {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }()

    func start() async throws {
        startCalled = true
    }

    func stop() async {
        stopCalled = true
        continuation?.finish()
    }

    func emit(_ host: DiscoveredHost) {
        continuation?.yield(host)
    }
}

// MARK: - D.1 Tests — BroadcastDiscovery protocol contract

final class BroadcastDiscoveryTests: XCTestCase {

    func test_fakeBroadcastDiscovery_emitsOneHost() async throws {
        let fake = FakeBroadcastDiscovery()
        try await fake.start()
        XCTAssertTrue(fake.startCalled)

        let host = DiscoveredHost(name: "Test Mac", ipv4: "192.168.1.10", port: 4545, lastSeen: Date())
        var collected: [DiscoveredHost] = []

        let collectTask = Task {
            for await h in fake.hosts {
                collected.append(h)
            }
        }

        fake.emit(host)
        await fake.stop()
        await collectTask.value

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected.first, host)
    }

    func test_fakeBroadcastDiscovery_emitsTwoHosts_inOrder() async throws {
        let fake = FakeBroadcastDiscovery()
        try await fake.start()

        let h1 = DiscoveredHost(name: "Mac 1", ipv4: "192.168.1.10", port: 4545, lastSeen: Date())
        let h2 = DiscoveredHost(name: "Mac 2", ipv4: "192.168.1.11", port: 4545, lastSeen: Date())
        var collected: [DiscoveredHost] = []

        let collectTask = Task {
            for await h in fake.hosts {
                collected.append(h)
            }
        }

        fake.emit(h1)
        fake.emit(h2)
        await fake.stop()
        await collectTask.value

        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0], h1)
        XCTAssertEqual(collected[1], h2)
    }

    func test_fakeBroadcastDiscovery_stopCallsFinish() async throws {
        let fake = FakeBroadcastDiscovery()
        try await fake.start()

        let collectTask = Task {
            var count = 0
            for await _ in fake.hosts { count += 1 }
            return count
        }

        await fake.stop()
        let total = await collectTask.value
        XCTAssertTrue(fake.stopCalled)
        XCTAssertEqual(total, 0)
    }
}

// MARK: - D.3 Tests — ProbeCodec parsing

final class ProbeCodecTests: XCTestCase {

    // Valid response: "INKB!1|4545|MacBook Pro"
    func test_parse_validResponse_returnsHost() {
        let sourceIP = "192.168.1.5"
        let payload = "INKB!1|4545|MacBook Pro"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: sourceIP)

        XCTAssertNotNil(host)
        XCTAssertEqual(host?.ipv4, sourceIP)
        XCTAssertEqual(host?.port, 4545)
        XCTAssertEqual(host?.name, "MacBook Pro")
    }

    // Hostname with spaces and hyphens (macOS sanitizes to ASCII, but hyphen/space are valid)
    func test_parse_hostnameWithHyphen_succeeds() {
        let payload = "INKB!1|4545|Mac-Mini-Home"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: "10.0.0.1")
        XCTAssertNotNil(host)
        XCTAssertEqual(host?.name, "Mac-Mini-Home")
    }

    func test_parse_hostnameWithSpace_succeeds() {
        let payload = "INKB!1|4545|Mac Studio"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: "10.0.0.2")
        XCTAssertNotNil(host)
        XCTAssertEqual(host?.name, "Mac Studio")
    }

    // Bad magic header
    func test_parse_wrongMagic_returnsNil() {
        let payload = "BAD!1|4545|MacBook Pro"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: "192.168.1.5")
        XCTAssertNil(host)
    }

    // Missing fields
    func test_parse_missingPort_returnsNil() {
        let payload = "INKB!1|MacBook Pro"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: "192.168.1.5")
        XCTAssertNil(host)
    }

    func test_parse_emptyPayload_returnsNil() {
        let host = ProbeCodec.parseReply(Data(), sourceIP: "192.168.1.5")
        XCTAssertNil(host)
    }

    func test_parse_nonNumericPort_returnsNil() {
        let payload = "INKB!1|abc|MacBook Pro"
        let host = ProbeCodec.parseReply(Data(payload.utf8), sourceIP: "192.168.1.5")
        XCTAssertNil(host)
    }

    // Probe TX payload
    func test_probePayload_isINKBQuestion() {
        let probe = ProbeCodec.probePayload
        XCTAssertEqual(probe, Data("INKB?".utf8))
    }
}
