import Foundation

/// Pure utility for locating the `adb` binary on the host machine.
///
/// No I/O beyond `FileManager.isExecutableFile` — fully unit-testable by
/// injecting a mock `FileManager` and a custom environment dictionary.
public enum AdbDiscovery {

    /// Searches well-known locations for the `adb` binary and returns the
    /// first executable path found, or `nil` if none exists.
    ///
    /// Search order:
    /// 1. `$ANDROID_HOME/platform-tools/adb`
    /// 2. `$ANDROID_SDK_ROOT/platform-tools/adb`
    /// 3. `~/Library/Android/sdk/platform-tools/adb` (home from `$HOME`)
    /// 4. `/opt/homebrew/bin/adb`
    /// 5. `/usr/local/bin/adb`
    public static func findAdb(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        let candidates = buildCandidates(environment: environment)
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    // MARK: - Private

    private static func buildCandidates(environment: [String: String]) -> [String] {
        var paths: [String] = []

        // 1. $ANDROID_HOME
        if let androidHome = environment["ANDROID_HOME"], !androidHome.isEmpty {
            paths.append("\(androidHome)/platform-tools/adb")
        }

        // 2. $ANDROID_SDK_ROOT
        if let androidSdkRoot = environment["ANDROID_SDK_ROOT"], !androidSdkRoot.isEmpty {
            paths.append("\(androidSdkRoot)/platform-tools/adb")
        }

        // 3. ~/Library/Android/sdk — expand ~ using $HOME
        let home = environment["HOME"] ?? NSHomeDirectory()
        paths.append("\(home)/Library/Android/sdk/platform-tools/adb")

        // 4. Homebrew (Apple Silicon)
        paths.append("/opt/homebrew/bin/adb")

        // 5. Homebrew (Intel) / manual install
        paths.append("/usr/local/bin/adb")

        return paths
    }
}
