// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkBridge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "InkBridge", targets: ["InkBridge"]),
        .library(name: "InkBridgeCore", targets: ["InkBridgeCore"]),
    ],
    targets: [
        // SwiftUI app — @main entry point
        .executableTarget(
            name: "InkBridge",
            dependencies: ["InkBridgeCore"],
            path: "Sources/InkBridge",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Domain / transport / injection library (importable in tests without the app target)
        .target(
            name: "InkBridgeCore",
            path: "Sources/InkBridgeCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        // Unit tests — run with `swift test`
        // Vectors/ contains copies of protocol/test-vectors/*.hex embedded in the test bundle.
        // NOTE: if you edit the canonical vectors in protocol/test-vectors/, re-copy them here.
        .testTarget(
            name: "InkBridgeCoreTests",
            dependencies: ["InkBridgeCore"],
            path: "Tests/InkBridgeCoreTests",
            resources: [.copy("Vectors")]
        ),
    ]
)
