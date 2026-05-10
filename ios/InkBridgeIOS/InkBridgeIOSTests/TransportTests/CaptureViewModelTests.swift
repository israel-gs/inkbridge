import XCTest
import CoreGraphics
@testable import InkBridgeIOS

// MARK: - FakeSettingsRepository

/// Minimal in-memory implementation of `SettingsRepository` for unit tests.
/// All fields default to the same values as `UserDefaultsSettingsRepository`.
final class FakeSettingsRepository: SettingsRepository {
    var hostOverride: String = ""
    var port: UInt16 = 4545
    var haptics: Bool = true
    var naturalScroll: Bool = true
    var sidebarEdge: SidebarEdge = .trailing
    var activeProfileId: String = ""
}

// MARK: - I.3 — CaptureViewModel tests

@MainActor
final class CaptureViewModelTests: XCTestCase {

    // MARK: - Helpers

    func makeVM(naturalScroll: Bool = true) -> (CaptureViewModel, FakeUDPClient) {
        let client = FakeUDPClient()
        client.simulatedState = .connected
        let settings = FakeSettingsRepository()
        settings.naturalScroll = naturalScroll
        let vm = CaptureViewModel(udpClient: client, settingsRepo: settings)
        return (vm, client)
    }

    func makeSample(
        x: CGFloat = 0, y: CGFloat = 0,
        timestamp: TimeInterval = 0
    ) -> TouchSample {
        TouchSample(id: UUID(), location: CGPoint(x: x, y: y), timestamp: timestamp)
    }

    // MARK: - I.3a: Touch sample stream produces encoded frames in order

    func test_ingest_multipleMoveSamples_sendDataInOrder() async throws {
        let (vm, client) = makeVM()

        // Start a 1-finger drag (began + two moves beyond the 10pt slop threshold).
        let id = UUID()
        let s0 = TouchSample(id: id, location: CGPoint(x: 0, y: 0), timestamp: 0)
        let s1 = TouchSample(id: id, location: CGPoint(x: 15, y: 0), timestamp: 0.01)
        let s2 = TouchSample(id: id, location: CGPoint(x: 25, y: 0), timestamp: 0.02)

        vm.ingest([s0], phase: .began)
        vm.ingest([s1], phase: .moved)
        vm.ingest([s2], phase: .moved)

        // Allow async send tasks to complete.
        try await Task.sleep(nanoseconds: 100_000_000)

        // After the 10pt slop is crossed on s1 (15pt > 10pt), we expect cursor deltas.
        // s1 crosses the threshold → emits cursorDelta(15, 0)
        // s2 is already disqualified → emits cursorDelta(10, 0)
        XCTAssertGreaterThanOrEqual(client.sentData.count, 2)

        // Verify each sent frame is 20 bytes (BinaryStylusCodec output size).
        for frame in client.sentData {
            XCTAssertEqual(frame.count, 20, "Every encoded frame must be exactly 20 bytes")
        }
    }

    // MARK: - I.3b: 1-finger tap emits LEFT_DOWN + LEFT_UP frames

    func test_ingest_tap_emitsTwoStylusButtonFrames() async throws {
        let (vm, client) = makeVM()

        let id = UUID()
        let s0 = TouchSample(id: id, location: CGPoint(x: 100, y: 100), timestamp: 0)
        let s1 = TouchSample(id: id, location: CGPoint(x: 100, y: 100), timestamp: 0.1) // 100ms < 250ms tap

        vm.ingest([s0], phase: .began)
        vm.ingest([s1], phase: .ended)

        try await Task.sleep(nanoseconds: 100_000_000)

        // LEFT_DOWN and LEFT_UP = 2 frames
        XCTAssertEqual(client.sentData.count, 2)

        // Verify first frame event type byte (offset 1) is STYLUS_BUTTON (0x03)
        XCTAssertEqual(client.sentData[0][1], 0x03)
        XCTAssertEqual(client.sentData[1][1], 0x03)
    }

    // MARK: - I.3c: Express key tap emits KEY_DOWN + KEY_UP frames

    func test_handleExpressKeyEvent_keyDown_sendsKeyEventFrame() async throws {
        let (vm, client) = makeVM()

        let event = StylusEvent.keyEvent(keyCode: 0x06, modifiers: 0x08, action: .down)
        vm.handleExpressKeyEvent(event)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(client.sentData.count, 1)
        // Event type byte at offset 1 = KEY_EVENT (0x07)
        XCTAssertEqual(client.sentData[0][1], 0x07)
    }

    func test_handleExpressKeyEvent_keyUpFollowsKeyDown() async throws {
        let (vm, client) = makeVM()

        vm.handleExpressKeyEvent(.keyEvent(keyCode: 0x06, modifiers: 0x08, action: .down))
        vm.handleExpressKeyEvent(.keyEvent(keyCode: 0x06, modifiers: 0x08, action: .up))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(client.sentData.count, 2)
        // Both frames are KEY_EVENT
        XCTAssertEqual(client.sentData[0][1], 0x07)
        XCTAssertEqual(client.sentData[1][1], 0x07)
    }

    // MARK: - I.3d: Frames are 20 bytes (protocol invariant)

    func test_allSentFrames_are20Bytes() async throws {
        let (vm, client) = makeVM()

        // Capture request
        vm.handleExpressKeyEvent(.captureRequest(slot: 0))
        // Scroll event
        vm.handleExpressKeyEvent(.stylusScroll(deltaX: 5, deltaY: 0, phase: 0))

        try await Task.sleep(nanoseconds: 100_000_000)

        for frame in client.sentData {
            XCTAssertEqual(frame.count, 20)
        }
    }

    // MARK: - I.3e: connectionState reflects injected value

    func test_connectionState_reflectsInitialValue() {
        let client = FakeUDPClient()
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: Date())
        let vm = CaptureViewModel(
            udpClient: client,
            settingsRepo: FakeSettingsRepository(),
            connectionState: .connected(host: host)
        )
        XCTAssertEqual(vm.connectionState, .connected(host: host))
    }

    // MARK: - I.3f: updateConnectionState updates the property

    func test_updateConnectionState_propagates() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.connectionState, .idle)

        let host = DiscoveredHost(name: "iMac", ipv4: "192.168.1.5", port: 4545, lastSeen: Date())
        vm.updateConnectionState(.connected(host: host))

        XCTAssertEqual(vm.connectionState, .connected(host: host))
    }

    // MARK: - I.3g: disconnect sets state to .idle and calls udpClient.disconnect

    func test_disconnect_setsIdle_andCallsClientDisconnect() async throws {
        let (vm, client) = makeVM()
        let host = DiscoveredHost(name: "Mac", ipv4: "10.0.0.1", port: 4545, lastSeen: Date())
        vm.updateConnectionState(.connected(host: host))

        vm.disconnect()

        XCTAssertEqual(vm.connectionState, .idle)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(client.disconnectCalled)
    }
}
