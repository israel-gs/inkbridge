import XCTest
@testable import InkBridgeCore

/// Tests for ``ProcessAdbRunner`` timeout and process-termination behaviour (Bug 5 fix).
///
/// Spawning a real ``Foundation.Process`` is the only way to verify that the OS
/// process is actually terminated (as opposed to just the Swift Task being cancelled).
///
/// Strategy: write a tiny shell script that ignores its arguments and sleeps
/// for 30 seconds to the test temp directory. ``ProcessAdbRunner`` is pointed at
/// that script as the "adb binary". This reliably simulates a hung adb process.
final class AdbRunnerTimeoutTests: XCTestCase {

    // MARK: - Helpers

    /// Path to `true`, which exits immediately with code 0.
    private static let truePath = "/usr/bin/true"

    /// Creates a self-contained shell script that ignores its arguments and
    /// sleeps for 30 seconds. Returns the path to the script.
    private func makeHangingScript() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inkbridge-hang-adb-\(ProcessInfo.processInfo.processIdentifier).sh")
        let script = "#!/bin/sh\nsleep 30\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url.path
    }

    // MARK: - Timeout: process terminates

    /// When the adb process hangs beyond the timeout, ``ProcessAdbRunner`` must:
    /// 1. Throw ``AdbRunnerError.timeout``.
    /// 2. Return within timeout + 2-second grace (the process was terminated).
    ///
    /// Without the Bug 5 fix, `sleep 30` inside the script would keep running as
    /// a zombie after the Swift Task was cancelled. With the fix, `terminate()` is
    /// called on the ``Foundation.Process`` so the child exits promptly and the test
    /// completes well inside the grace window.
    func testTimeoutThrowsAdbRunnerErrorTimeout() async throws {
        let scriptPath = try makeHangingScript()
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        // Use a tiny timeout so the test is fast.
        let runner = ProcessAdbRunner(adbPath: scriptPath, timeout: 0.3)

        let start = Date()
        do {
            _ = try await runner.devices()
            XCTFail("Expected AdbRunnerError.timeout, but succeeded")
        } catch AdbRunnerError.timeout {
            // Correct error.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let elapsed = Date().timeIntervalSince(start)
        // Must return within timeout (0.3 s) + 2 s grace for terminate() + test overhead.
        XCTAssertLessThan(
            elapsed,
            0.3 + 2.0,
            "Timed-out run must return within timeout + 2 s grace; took \(elapsed) s"
        )
    }

    /// A fast-completing process must not be affected — the normal success path
    /// must still work after the ProcessHandle refactor.
    func testNonHangingProcessCompletesSuccessfully() async throws {
        // `true` exits immediately with code 0. The output is empty so
        // `devices()` returns an empty list — the key is no exception is thrown.
        let runner = ProcessAdbRunner(adbPath: Self.truePath, timeout: 5.0)

        do {
            let devices = try await runner.devices()
            XCTAssertNotNil(devices, "devices() must return a (possibly empty) list")
        } catch {
            XCTFail("Non-hanging process must not throw: \(error)")
        }
    }

    /// Rapid consecutive invocations must each respect their own timeout and not
    /// accumulate zombie processes that would slow down the test suite.
    func testMultipleTimeoutsDoNotLeakProcesses() async throws {
        let scriptPath = try makeHangingScript()
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let runner = ProcessAdbRunner(adbPath: scriptPath, timeout: 0.2)

        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    _ = try? await runner.devices()
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)

        // 3 parallel timeouts of 0.2 s each + 2 s grace per process.
        // If processes leaked and kept the kernel busy, this would easily exceed
        // the bound. 0.2 + 3.0 = 3.2 s is generous but tight enough to catch leaks.
        XCTAssertLessThan(
            elapsed,
            0.2 + 3.0,
            "3 parallel timed-out runs must complete within grace window; took \(elapsed) s"
        )
    }
}
