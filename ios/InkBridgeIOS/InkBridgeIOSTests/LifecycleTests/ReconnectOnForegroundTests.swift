import XCTest
import SwiftUI
@testable import InkBridgeIOS

// MARK: - J.1 — ReconnectOnForegroundTests

/// Tests the lifecycle reconnect behaviour of `ConnectionViewModel`.
///
/// # Spec reference — §Reconnection / Lifecycle
/// - On `.background`: disconnect (no UDP traffic to idle host), preserve last host.
/// - On `.active` after a prior connection: attempt reconnect within
///   `RECONNECT_ON_FOREGROUND_BUDGET_S = 1 s`.
/// - On `.active` with NO prior connection: no reconnect attempt.
@MainActor
final class ReconnectOnForegroundTests: XCTestCase {

    // MARK: - Helpers

    func makeViewModel() -> (ConnectionViewModel, FakeUDPClient, FakeBroadcastDiscovery) {
        let client = FakeUDPClient()
        let discovery = FakeBroadcastDiscovery()
        let vm = ConnectionViewModel(udpClient: client, discovery: discovery)
        return (vm, client, discovery)
    }

    func makeHost(_ ip: String = "192.168.1.10", port: UInt16 = 4545) -> DiscoveredHost {
        DiscoveredHost(name: "TestMac", ipv4: ip, port: port, lastSeen: Date())
    }

    // MARK: - J.1a: Background → disconnect is called and state goes to .idle

    func test_background_disconnectsAndSetsIdle() async throws {
        let (vm, client, _) = makeViewModel()

        // Establish a connection first.
        vm.hostField = "192.168.1.10"
        vm.connect()
        try await Task.sleep(nanoseconds: 100_000_000) // 100 ms — let connect() complete

        // Now go to background.
        vm.handleScenePhase(.background)
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms

        XCTAssertEqual(vm.connectionState, .idle, "State must be .idle after background")
        // disconnect() is called from background transition (disconnect task fired).
        // FakeUDPClient.disconnectCalled tracks both calls; we care it was called at least once.
        XCTAssertTrue(client.disconnectCalled, "UDP client must be disconnected on background")
    }

    // MARK: - J.1b: Active after prior connection → reconnect fires within 1 s budget

    func test_foreground_afterPriorConnection_reconnects() async throws {
        let (vm, client, _) = makeViewModel()

        // 1. Connect (sets lastConnectedHost internally).
        vm.hostField = "192.168.1.10"
        vm.port = 4545
        vm.connect()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify we are connected.
        if case .connected = vm.connectionState { } else {
            XCTFail("Expected .connected after initial connect; got \(vm.connectionState)")
        }

        let connectCountAfterFirst = client.connectCalledCount

        // 2. Background — clears transport but preserves last host.
        vm.handleScenePhase(.background)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.connectionState, .idle)

        // 3. Foreground — should trigger reconnect within RECONNECT_ON_FOREGROUND_BUDGET_S (1 s).
        vm.handleScenePhase(.active)

        // Budget = 1 s. We check within 500 ms (well within budget).
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertGreaterThan(
            client.connectCalledCount,
            connectCountAfterFirst,
            "Reconnect must fire within 1s foreground budget when a prior host exists"
        )
    }

    // MARK: - J.1c: Active with NO prior connection → no reconnect attempt

    func test_foreground_withoutPriorConnection_doesNotReconnect() async throws {
        let (vm, client, _) = makeViewModel()

        // Never connected — no lastConnectedHost cached.
        vm.handleScenePhase(.active)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(client.connectCalled, "No reconnect should fire when no host was previously connected")
    }

    // MARK: - J.1d: After explicit disconnect, foreground does NOT reconnect (user chose to disconnect)

    func test_foreground_afterExplicitDisconnect_doesNotReconnect() async throws {
        let (vm, client, _) = makeViewModel()

        // Connect, then the user explicitly disconnects.
        vm.hostField = "10.0.0.1"
        vm.connect()
        try await Task.sleep(nanoseconds: 100_000_000)

        let connectCountAfterFirst = client.connectCalledCount

        // Explicit disconnect clears lastConnectedHost.
        vm.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Foreground — should NOT reconnect.
        vm.handleScenePhase(.active)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(
            client.connectCalledCount,
            connectCountAfterFirst,
            "After an explicit user disconnect, foreground must not auto-reconnect"
        )
    }

    // MARK: - J.1e: Same host is reused after background → foreground (persistence test)

    func test_foreground_reusesLastConnectedHost() async throws {
        let (vm, client, _) = makeViewModel()

        let targetIP = "192.168.1.77"
        vm.hostField = targetIP
        vm.port = 4545
        vm.connect()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Background — preserve last host.
        vm.handleScenePhase(.background)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Clear hostField to verify it's restored from cached host, not from current field.
        vm.hostField = ""

        vm.handleScenePhase(.active)
        try await Task.sleep(nanoseconds: 300_000_000)

        // hostField should be repopulated from lastConnectedHost by connect(to:).
        XCTAssertEqual(vm.hostField, targetIP, "Reconnect must reuse the last connected IP")
    }
}

// MARK: - FakeUDPClient convenience for call counting

extension FakeUDPClient {
    /// Total number of times `connect(host:port:)` has been called.
    /// Uses the `sentConnectHosts` array defined on `FakeUDPClient`.
    var connectCalledCount: Int { sentConnectHosts.count }
}
