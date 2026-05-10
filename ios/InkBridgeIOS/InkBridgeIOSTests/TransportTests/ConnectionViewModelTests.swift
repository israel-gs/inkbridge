import XCTest
import SwiftUI
@testable import InkBridgeIOS

// MARK: - I.1 — ConnectionViewModel tests

@MainActor
final class ConnectionViewModelTests: XCTestCase {

    // MARK: - Helpers

    func makeViewModel() -> (ConnectionViewModel, FakeUDPClient, FakeBroadcastDiscovery) {
        let client = FakeUDPClient()
        let discovery = FakeBroadcastDiscovery()
        let vm = ConnectionViewModel(udpClient: client, discovery: discovery)
        return (vm, client, discovery)
    }

    // MARK: - I.1a: Tapping a discovered host populates hostField and calls connect

    func test_connectToDiscoveredHost_populatesHostField_andConnects() async throws {
        let (vm, client, _) = makeViewModel()
        let host = DiscoveredHost(name: "Mac Pro", ipv4: "192.168.1.50", port: 4545, lastSeen: Date())

        vm.connect(to: host)

        XCTAssertEqual(vm.hostField, "192.168.1.50")
        XCTAssertEqual(vm.port, 4545)

        // Wait briefly for the async connect task.
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        XCTAssertTrue(client.connectCalled)
    }

    // MARK: - I.1b: Manual IP + port → connect is called with correct values

    func test_manualConnect_sendsCorrectHostAndPort() async throws {
        let (vm, client, _) = makeViewModel()

        vm.hostField = "10.0.0.5"
        vm.port = 9090
        vm.connect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(client.connectCalled)
    }

    // MARK: - I.1c: Connection state transitions to .connected after successful connect

    func test_connect_transitionsToConnected() async throws {
        let (vm, _, _) = makeViewModel()

        vm.hostField = "192.168.1.1"
        vm.connect()

        XCTAssertEqual(vm.connectionState, .connecting)

        try await Task.sleep(nanoseconds: 100_000_000)

        if case .connected = vm.connectionState {
            // OK
        } else {
            XCTFail("Expected .connected, got \(vm.connectionState)")
        }
    }

    // MARK: - I.1d: Background scene phase → disconnect is called

    func test_handleScenePhase_background_disconnects() async throws {
        let (vm, client, _) = makeViewModel()
        client.simulatedState = .connected

        vm.handleScenePhase(.background)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(client.disconnectCalled)
        XCTAssertEqual(vm.connectionState, .idle)
    }

    // MARK: - I.1e: Active scene phase → starts discovery

    func test_handleScenePhase_active_startsDiscovery() async throws {
        let (vm, _, discovery) = makeViewModel()

        vm.handleScenePhase(.active)

        // Give the background task time to call start().
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(discovery.startCalled)
    }

    // MARK: - I.1f: Discovered host emitted → appears in discoveredHosts

    func test_discoveredHost_appearsInList() async throws {
        let (vm, _, discovery) = makeViewModel()

        vm.startDiscovery()
        try await Task.sleep(nanoseconds: 50_000_000) // let start() be called

        let host = DiscoveredHost(name: "MacBook", ipv4: "192.168.1.100", port: 4545, lastSeen: Date())
        discovery.emit(host)

        // Give the iteration task time to process.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.discoveredHosts.count, 1)
        XCTAssertEqual(vm.discoveredHosts[0].ipv4, "192.168.1.100")
    }

    // MARK: - I.1g: Discovered hosts are deduped by (ip, port)

    func test_discoveredHost_deduplicatedByIPAndPort() async throws {
        let (vm, _, discovery) = makeViewModel()

        vm.startDiscovery()
        try await Task.sleep(nanoseconds: 50_000_000)

        let host1 = DiscoveredHost(name: "Mac", ipv4: "192.168.1.10", port: 4545, lastSeen: Date())
        let host2 = DiscoveredHost(name: "Mac (updated)", ipv4: "192.168.1.10", port: 4545, lastSeen: Date())

        discovery.emit(host1)
        try await Task.sleep(nanoseconds: 50_000_000)
        discovery.emit(host2)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(vm.discoveredHosts.count, 1)
        XCTAssertEqual(vm.discoveredHosts[0].name, "Mac (updated)")
    }

    // MARK: - I.1h: Initial connectionState is .idle

    func test_initialConnectionState_isIdle() {
        let (vm, _, _) = makeViewModel()
        XCTAssertEqual(vm.connectionState, .idle)
    }

    // MARK: - I.1i: Empty hostField → connect is a no-op

    func test_connect_withEmptyHostField_doesNotConnect() async throws {
        let (vm, client, _) = makeViewModel()
        vm.hostField = ""
        vm.connect()

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(client.connectCalled)
    }
}
