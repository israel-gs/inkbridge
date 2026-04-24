import Foundation

/// Port for interacting with the `adb` binary.
///
/// Implementations may be real (spawn a `Foundation.Process`) or mock (for
/// testing). Never call the real binary in tests — inject a mock instead.
public protocol AdbRunner: Sendable {
    /// Returns the list of device serials currently connected in "device" state.
    func devices() async throws -> [String]
    /// Establishes `adb reverse tcp:<local> tcp:<remote>`. Idempotent — re-running is OK.
    func reverse(local: UInt16, remote: UInt16) async throws
}

/// Errors thrown by ``AdbRunner`` implementations.
public enum AdbRunnerError: Error, Equatable {
    /// The `adb` binary was not found at the given path.
    case adbNotFound
    /// The process exited with a non-zero code.
    case nonZeroExit(code: Int32, stderr: String)
    /// The process did not finish within the timeout.
    case timeout
}

// MARK: - Real implementation

/// Spawns `adb` as a child process via `Foundation.Process`.
///
/// All work is done on background queues. A 5-second timeout is applied to
/// every invocation — if the process does not terminate in time the task
/// throws ``AdbRunnerError/timeout``.
public final class ProcessAdbRunner: AdbRunner, @unchecked Sendable {

    private let adbPath: String
    private let timeout: TimeInterval

    public init(adbPath: String, timeout: TimeInterval = 5) {
        self.adbPath = adbPath
        self.timeout = timeout
    }

    // MARK: - AdbRunner

    public func devices() async throws -> [String] {
        let output = try await run(arguments: ["devices"])
        return parseDevices(from: output.stdout)
    }

    public func reverse(local: UInt16, remote: UInt16) async throws {
        let output = try await run(arguments: ["reverse", "tcp:\(local)", "tcp:\(remote)"])
        if output.exitCode != 0 {
            throw AdbRunnerError.nonZeroExit(code: output.exitCode, stderr: output.stderr)
        }
    }

    // MARK: - Private

    private struct ProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func run(arguments: [String]) async throws -> ProcessOutput {
        // Use a Task with timeout rather than DispatchWorkItem to avoid
        // Sendable issues with DispatchWorkItem.
        let timeoutSeconds = self.timeout
        let adbPath = self.adbPath

        return try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
            group.addTask {
                try await ProcessAdbRunner.spawnProcess(adbPath: adbPath, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw AdbRunnerError.timeout
            }

            // Return the first result (either the process output or timeout).
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func spawnProcess(adbPath: String, arguments: [String]) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: ProcessOutput(
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AdbRunnerError.adbNotFound)
            }
        }
    }

    /// Parses `adb devices` stdout into a list of connected device serials.
    ///
    /// Lines after "List of devices attached" that end in `\tdevice` are live
    /// devices. Lines ending in `unauthorized`, `offline`, or blank are ignored.
    private func parseDevices(from output: String) -> [String] {
        var serials: [String] = []
        var pastHeader = false

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("List of devices attached") {
                pastHeader = true
                continue
            }
            guard pastHeader else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 2, parts[1].trimmingCharacters(in: .whitespaces) == "device" else {
                continue
            }
            serials.append(parts[0])
        }

        return serials
    }
}
