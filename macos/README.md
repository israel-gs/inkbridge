# InkBridge — macOS

Swift Package for the macOS server side of InkBridge.

## Build

```bash
swift build
```

## Test

```bash
swift test
```

## Open in Xcode

```bash
open Package.swift
```

Xcode will import the package and make `cmd+U` available for running tests.

## Structure

- `Sources/InkBridge/` — SwiftUI app (`@main` entry point, `ContentView`)
- `Sources/InkBridgeCore/` — Domain, transport, injection (importable by tests without the app target)
- `Tests/InkBridgeCoreTests/` — XCTest unit tests

Phase 1 will populate `InkBridgeCore` with the binary codec, NWListener transports, and `CGEventPost` injection.
