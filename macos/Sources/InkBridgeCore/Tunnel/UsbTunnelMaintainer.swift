import Foundation

/// Observable state of the USB reverse-tunnel watchdog.
public enum UsbTunnelState: Equatable, Sendable {
    /// `adb` is not found, or an unrecoverable error was encountered.
    case unavailable(reason: String)
    /// `adb` is reachable but no device is currently connected.
    case idle
    /// At least one device is connected and the reverse tunnel is active.
    case active(deviceCount: Int)
}

/// Watchdog that keeps `adb reverse tcp:<port> tcp:<port>` alive.
///
/// Polls every `interval` seconds. If the runner is `nil` (adb not found) the
/// maintainer starts in `.unavailable` and `start()` is a no-op. On errors the
/// state transitions to `.unavailable` but the poll loop continues — recovery
/// is automatic when the device reconnects.
@MainActor
public final class UsbTunnelMaintainer: ObservableObject {

    @Published public private(set) var state: UsbTunnelState = .idle

    private let runner: AdbRunner?
    private let port: UInt16
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    public init(runner: AdbRunner?, port: UInt16, interval: TimeInterval = 2.0) {
        self.runner = runner
        self.port = port
        self.interval = interval

        if runner == nil {
            self.state = .unavailable(reason: "adb not found")
        }
    }

    // MARK: - Lifecycle

    public func start() {
        guard let runner else { return }  // nil runner → no-op

        task = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.tick(runner: runner)
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Private

    private func tick(runner: AdbRunner) async {
        do {
            let connectedDevices = try await runner.devices()

            if connectedDevices.isEmpty {
                state = .idle
                return
            }

            try await runner.reverse(local: port, remote: port)
            state = .active(deviceCount: connectedDevices.count)
        } catch let error as AdbRunnerError {
            state = .unavailable(reason: describeError(error))
        } catch {
            state = .unavailable(reason: error.localizedDescription)
        }
    }

    private func describeError(_ error: AdbRunnerError) -> String {
        switch error {
        case .adbNotFound:
            return "adb not found"
        case .nonZeroExit(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "adb exited with code \(code)" : detail
        case .timeout:
            return "adb timed out"
        }
    }
}
