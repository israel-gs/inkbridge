import XCTest
@testable import InkBridgeCore

// MARK: - MockAdbRunner

/// Test double for ``AdbRunner``.
///
/// Controls what `devices()` and `reverse(local:remote:)` return. Tracks call
/// counts so tests can assert the watchdog stopped ticking after `stop()`.
final class MockAdbRunner: AdbRunner, @unchecked Sendable {

    // MARK: - Configurable responses

    /// Serials returned by the next `devices()` call. Cycled in order; the
    /// last element is repeated once exhausted.
    var deviceSequence: [[String]] = [[]]
    private var deviceCallIndex = 0

    /// When non-nil, `devices()` throws this error instead.
    var devicesError: Error?

    /// When non-nil, `reverse(local:remote:)` throws this error instead.
    var reverseError: Error?

    // MARK: - Observation

    private(set) var devicesCallCount = 0
    private(set) var reverseCallCount = 0

    // MARK: - AdbRunner

    func devices() async throws -> [String] {
        devicesCallCount += 1

        if let error = devicesError {
            throw error
        }

        let index = min(deviceCallIndex, deviceSequence.count - 1)
        let result = deviceSequence[index]
        deviceCallIndex += 1
        return result
    }

    func reverse(local: UInt16, remote: UInt16) async throws {
        reverseCallCount += 1

        if let error = reverseError {
            throw error
        }
    }
}

// MARK: - Tests

/// Tests for ``UsbTunnelMaintainer``.
///
/// Uses a short interval (0.05 s) so ticks fire quickly. Every test cancels
/// the maintainer in `tearDown` to avoid background tasks escaping.
@MainActor
final class UsbTunnelMaintainerTests: XCTestCase {

    private static let interval: TimeInterval = 0.05

    private var mock: MockAdbRunner!
    private var maintainer: UsbTunnelMaintainer!

    override func setUp() {
        super.setUp()
        mock = MockAdbRunner()
    }

    override func tearDown() {
        maintainer?.stop()
        maintainer = nil
        mock = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMaintainer() -> UsbTunnelMaintainer {
        UsbTunnelMaintainer(runner: mock, port: 4545, interval: Self.interval)
    }

    private func makeMaintainer(runner: AdbRunner?) -> UsbTunnelMaintainer {
        UsbTunnelMaintainer(runner: runner, port: 4545, interval: Self.interval)
    }

    /// Waits until `maintainer.state == expected` or times out.
    private func waitForState(
        _ expected: UsbTunnelState,
        timeout: TimeInterval = 2.0,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while maintainer.state != expected, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10 ms
        }
        XCTAssertEqual(maintainer.state, expected, file: file, line: line)
    }

    // MARK: - Tests

    func testNoDeviceTransitionsToIdle() async {
        mock.deviceSequence = [[]]  // no devices
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.idle)
    }

    func testDeviceAppearsTransitionsToActive() async {
        mock.deviceSequence = [["emulator-5554"]]
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.active(deviceCount: 1))
    }

    func testMultipleDevicesReportedCorrectly() async {
        mock.deviceSequence = [["emulator-5554", "device-123"]]
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.active(deviceCount: 2))
    }

    func testDeviceDisappearsTransitionsBackToIdle() async {
        // First tick: device present → active.
        // Second tick: no device → idle.
        mock.deviceSequence = [["emulator-5554"], []]
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.active(deviceCount: 1))
        await waitForState(.idle)
    }

    func testReverseFailureTransitionsToUnavailable() async {
        mock.deviceSequence = [["emulator-5554"]]
        mock.reverseError = AdbRunnerError.nonZeroExit(code: 1, stderr: "no permissions")
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.unavailable(reason: "no permissions"))
    }

    func testTaskKeepsRunningAfterReverseFailure() async {
        // Tick 1: reverse fails → unavailable.
        // Tick 2: reverse succeeds → active (recovery is automatic).
        let runner = MockAdbRunner()
        runner.deviceSequence = [["emulator-5554"], ["emulator-5554"]]

        // Fail on first reverse call, succeed on subsequent ones.
        var reverseCallCount = 0
        // We can't mutate reverseCallCount inside the mock directly, so use a
        // custom mock subclass to vary behavior.
        let varyingMock = VaryingReverseMock()
        varyingMock.deviceSequence = [["emulator-5554"], ["emulator-5554"]]
        varyingMock.failFirstReverse = true

        maintainer = makeMaintainer(runner: varyingMock)
        maintainer.start()

        // Should first hit unavailable (due to reverse failure)…
        await waitForState(.unavailable(reason: "first reverse failed"))
        // …then recover to active on the next tick.
        await waitForState(.active(deviceCount: 1))

        _ = reverseCallCount // suppress unused warning
    }

    func testDevicesErrorTransitionsToUnavailable() async {
        mock.devicesError = AdbRunnerError.timeout
        maintainer = makeMaintainer()
        maintainer.start()

        await waitForState(.unavailable(reason: "adb timed out"))
    }

    func testDevicesErrorDoesNotStopTask() async {
        // First tick: throws → unavailable.
        // Second tick: succeeds with a device → active.
        let recovering = RecoveringMock()
        recovering.deviceSequence = [[], ["emulator-5554"]]
        recovering.failFirstCall = true

        maintainer = makeMaintainer(runner: recovering)
        maintainer.start()

        await waitForState(.unavailable(reason: "adb timed out"))
        await waitForState(.active(deviceCount: 1))
    }

    func testNilRunnerStartsInUnavailable() async {
        maintainer = makeMaintainer(runner: Optional<MockAdbRunner>.none)
        XCTAssertEqual(maintainer.state, .unavailable(reason: "adb not found"))
    }

    func testNilRunnerStartIsNoOp() async {
        let nilMaintainer = UsbTunnelMaintainer(runner: Optional<MockAdbRunner>.none, port: 4545)
        nilMaintainer.start()
        // Give it time to tick (it shouldn't).
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(nilMaintainer.state, .unavailable(reason: "adb not found"))
        nilMaintainer.stop()
    }

    func testStopPreventsAdditionalTicks() async {
        mock.deviceSequence = [["emulator-5554"]]
        maintainer = makeMaintainer()
        maintainer.start()

        // Wait for at least one tick.
        await waitForState(.active(deviceCount: 1))
        let callCountAfterFirstTick = mock.devicesCallCount

        maintainer.stop()

        // Wait a few potential intervals and verify the count didn't grow.
        try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms — 6× the interval
        XCTAssertEqual(mock.devicesCallCount, callCountAfterFirstTick)
    }
}

// MARK: - Helper mocks for complex scenarios

/// Fails the first `reverse` call, succeeds on all subsequent ones.
private final class VaryingReverseMock: AdbRunner, @unchecked Sendable {
    var deviceSequence: [[String]] = [[]]
    var failFirstReverse = false
    private var reverseCallCount = 0
    private var deviceCallIndex = 0

    func devices() async throws -> [String] {
        let index = min(deviceCallIndex, deviceSequence.count - 1)
        let result = deviceSequence[index]
        deviceCallIndex += 1
        return result
    }

    func reverse(local: UInt16, remote: UInt16) async throws {
        reverseCallCount += 1
        if failFirstReverse && reverseCallCount == 1 {
            throw AdbRunnerError.nonZeroExit(code: 1, stderr: "first reverse failed")
        }
    }
}

/// Throws on the first `devices()` call, succeeds on subsequent ones.
private final class RecoveringMock: AdbRunner, @unchecked Sendable {
    var deviceSequence: [[String]] = [[]]
    var failFirstCall = false
    private var callCount = 0

    func devices() async throws -> [String] {
        callCount += 1
        if failFirstCall && callCount == 1 {
            throw AdbRunnerError.timeout
        }
        let index = min(callCount - 1, deviceSequence.count - 1)
        return deviceSequence[index]
    }

    func reverse(local: UInt16, remote: UInt16) async throws {}
}
