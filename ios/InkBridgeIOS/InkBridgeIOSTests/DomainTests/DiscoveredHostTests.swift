import XCTest
@testable import InkBridgeIOS

final class DiscoveredHostTests: XCTestCase {

    // MARK: - Equality (by IPv4 + port only)

    func testEqualityOnNetworkIdentity() {
        let a = DiscoveredHost(name: "MacBook Pro", ipv4: "192.168.1.5", port: 4545, lastSeen: Date(timeIntervalSince1970: 100))
        let b = DiscoveredHost(name: "Different Name", ipv4: "192.168.1.5", port: 4545, lastSeen: Date(timeIntervalSince1970: 999))
        // Name and lastSeen differ but IPv4 + port are the same → should be equal.
        XCTAssertEqual(a, b)
    }

    func testInequalityOnDifferentPort() {
        let a = DiscoveredHost(name: "Mac", ipv4: "192.168.1.5", port: 4545, lastSeen: Date())
        let b = DiscoveredHost(name: "Mac", ipv4: "192.168.1.5", port: 4546, lastSeen: Date())
        XCTAssertNotEqual(a, b)
    }

    func testInequalityOnDifferentIPv4() {
        let a = DiscoveredHost(name: "Mac", ipv4: "192.168.1.5", port: 4545, lastSeen: Date())
        let b = DiscoveredHost(name: "Mac", ipv4: "192.168.1.6", port: 4545, lastSeen: Date())
        XCTAssertNotEqual(a, b)
    }

    func testNameDifferenceDoesNotAffectEquality() {
        let t = Date()
        let a = DiscoveredHost(name: "Alpha", ipv4: "10.0.0.1", port: 4545, lastSeen: t)
        let b = DiscoveredHost(name: "Beta", ipv4: "10.0.0.1", port: 4545, lastSeen: t)
        XCTAssertEqual(a, b)
    }

    // MARK: - Staleness

    func testIsStaleWhenOlderThanThreshold() {
        let now = Date()
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: now.addingTimeInterval(-11))
        XCTAssertTrue(host.isStale(now: now, threshold: 10))
    }

    func testIsNotStaleWhenWithinThreshold() {
        let now = Date()
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: now.addingTimeInterval(-5))
        XCTAssertFalse(host.isStale(now: now, threshold: 10))
    }

    func testIsNotStaleAtExactThreshold() {
        let now = Date()
        // Exactly at the threshold: not stale (boundary is exclusive on the > side).
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: now.addingTimeInterval(-10))
        XCTAssertFalse(host.isStale(now: now, threshold: 10))
    }

    func testIsStaleJustPastThreshold() {
        let now = Date()
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: now.addingTimeInterval(-10.001))
        XCTAssertTrue(host.isStale(now: now, threshold: 10))
    }

    // MARK: - ConnectionState

    func testConnectionStateIdle() {
        let state = ConnectionState.idle
        if case .idle = state { } else { XCTFail("Expected .idle") }
    }

    func testConnectionStateConnecting() {
        let state = ConnectionState.connecting
        if case .connecting = state { } else { XCTFail("Expected .connecting") }
    }

    func testConnectionStateConnected() {
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: Date())
        let state = ConnectionState.connected(host: host)
        if case .connected(let h) = state {
            XCTAssertEqual(h.ipv4, "10.0.0.1")
        } else {
            XCTFail("Expected .connected")
        }
    }

    func testConnectionStateFailed() {
        let state = ConnectionState.failed(reason: "timeout")
        if case .failed(let r) = state {
            XCTAssertEqual(r, "timeout")
        } else {
            XCTFail("Expected .failed")
        }
    }

    func testConnectionStateEquatableIdle() {
        XCTAssertEqual(ConnectionState.idle, ConnectionState.idle)
        XCTAssertNotEqual(ConnectionState.idle, ConnectionState.connecting)
    }

    func testConnectionStateEquatableConnected() {
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: Date())
        XCTAssertEqual(ConnectionState.connected(host: host), ConnectionState.connected(host: host))
        XCTAssertNotEqual(ConnectionState.connected(host: host), ConnectionState.idle)
    }
}
