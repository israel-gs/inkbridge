import XCTest
@testable import InkBridgeCore

/// Tests for ``AdbDiscovery``.
///
/// Exercises every search path using a stub ``FileManager`` subclass and an
/// injected environment dictionary — the real filesystem is never touched.
final class AdbDiscoveryTests: XCTestCase {

    // MARK: - Stub FileManager

    /// Accepts only the paths in `executablePaths`.
    private final class StubFileManager: FileManager {
        var executablePaths: Set<String> = []

        override func isExecutableFile(atPath path: String) -> Bool {
            executablePaths.contains(path)
        }
    }

    // MARK: - Tests

    func testFindsViaAndroidHome() {
        let fm = StubFileManager()
        fm.executablePaths = ["/custom/android/platform-tools/adb"]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["ANDROID_HOME": "/custom/android", "HOME": "/Users/test"]
        )

        XCTAssertEqual(result, "/custom/android/platform-tools/adb")
    }

    func testFallsBackToAndroidSdkRoot() {
        let fm = StubFileManager()
        fm.executablePaths = ["/sdk/root/platform-tools/adb"]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["ANDROID_SDK_ROOT": "/sdk/root", "HOME": "/Users/test"]
        )

        XCTAssertEqual(result, "/sdk/root/platform-tools/adb")
    }

    func testFallsBackToHomeLibraryAndroid() {
        let fm = StubFileManager()
        fm.executablePaths = ["/Users/test/Library/Android/sdk/platform-tools/adb"]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["HOME": "/Users/test"]
        )

        XCTAssertEqual(result, "/Users/test/Library/Android/sdk/platform-tools/adb")
    }

    func testFallsBackToHomebrew() {
        let fm = StubFileManager()
        fm.executablePaths = ["/opt/homebrew/bin/adb"]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["HOME": "/Users/test"]
        )

        XCTAssertEqual(result, "/opt/homebrew/bin/adb")
    }

    func testFallsBackToUsrLocalBin() {
        let fm = StubFileManager()
        fm.executablePaths = ["/usr/local/bin/adb"]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["HOME": "/Users/test"]
        )

        XCTAssertEqual(result, "/usr/local/bin/adb")
    }

    func testReturnsNilWhenNothingExists() {
        let fm = StubFileManager()
        fm.executablePaths = []

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: ["HOME": "/Users/test"]
        )

        XCTAssertNil(result)
    }

    func testAndroidHomeTakesPrecedenceOverSdkRoot() {
        let fm = StubFileManager()
        // Both paths exist — ANDROID_HOME wins because it's checked first.
        fm.executablePaths = [
            "/home/platform-tools/adb",
            "/sdk/platform-tools/adb",
        ]

        let result = AdbDiscovery.findAdb(
            fileManager: fm,
            environment: [
                "ANDROID_HOME": "/home",
                "ANDROID_SDK_ROOT": "/sdk",
                "HOME": "/Users/test",
            ]
        )

        XCTAssertEqual(result, "/home/platform-tools/adb")
    }
}
