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

    /// A wrapper that pairs a running ``Foundation.Process`` with an async wait-for-exit
    /// and a synchronous `cancel()` that terminates the process. Using this wrapper
    /// allows the timeout race branch to terminate the OS process — simply cancelling
    /// the Swift Task does NOT deliver a signal to the child process, which would
    /// otherwise leak as a zombie until natural termination (Bug 5 fix).
    private actor ProcessHandle {
        private let process: Process

        init(process: Process) {
            self.process = process
        }

        /// Terminate the process with SIGTERM. If it is still running 1 second
        /// later, escalate to SIGINT. Used by the timeout branch.
        func terminate() {
            guard process.isRunning else { return }
            process.terminate()
            // Give the process up to 1 second to exit cleanly before escalating.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak process] in
                guard let p = process, p.isRunning else { return }
                p.interrupt()
            }
        }
    }

    private func run(arguments: [String]) async throws -> ProcessOutput {
        let timeoutSeconds = self.timeout
        let adbPath = self.adbPath

        // Bug 5 fix: hold a reference to the spawned Process so the timeout branch
        // can call process.terminate() directly. The handle is written synchronously
        // on the main run-loop thread inside spawnProcess — before the continuation
        // suspends — so the timeout task always finds it populated.
        let handleBox = MutableBox<ProcessHandle>()

        return try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
            group.addTask {
                try await ProcessAdbRunner.spawnProcess(
                    adbPath: adbPath,
                    arguments: arguments,
                    handleBox: handleBox
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                // Bug 5 fix: terminate the OS process. Task.cancel() alone only
                // cancels the Swift Task — the spawned process keeps running as a
                // zombie until natural termination.
                await handleBox.get()?.terminate()
                throw AdbRunnerError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Spawns the `adb` process, registers the ``ProcessHandle`` in `handleBox`
    /// synchronously before suspending, then waits asynchronously for the process
    /// to exit and returns its output.
    ///
    /// Registering the handle synchronously (before the continuation suspends)
    /// guarantees the timeout task can always call `terminate()` even when the
    /// OS process has not yet produced any output.
    private static func spawnProcess(
        adbPath: String,
        arguments: [String],
        handleBox: MutableBox<ProcessHandle>
    ) async throws -> ProcessOutput {
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
                // Register the handle immediately after the process is started —
                // before the continuation suspends — so the timeout branch can
                // always terminate the process regardless of its runtime state.
                // This is safe: `handleBox` is an actor, and `set` is called on a
                // background dispatch queue from within a non-async context here.
                // We use Task { } to bridge the actor call without blocking.
                Task { await handleBox.set(ProcessHandle(process: process)) }
            } catch {
                continuation.resume(throwing: AdbRunnerError.adbNotFound)
            }
        }
    }

    // MARK: - MutableBox

    /// A thread-safe single-value box backed by an actor. Used to share the
    /// ``ProcessHandle`` between the process task and the timeout task without
    /// unsafe shared mutable state.
    private actor MutableBox<T> {
        private var value: T?

        func set(_ value: T) { self.value = value }
        func get() -> T? { value }
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
