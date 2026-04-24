# Tasks: foundation

Each task is one session of focused work. Check off with `[x]` as it completes.

---

## Design Note: Spec vs. Design Conflict — HELLO Handshake

`transport.md R7` explicitly states: **"This change does NOT define a HELLO or version-negotiation handshake frame. The first frame sent MUST be a real event frame."**

`design.md §§2.3, 2.6, 2.7, 3.3, 4.1, 6` define a HELLO / HELLO_ACK exchange, HELLO payload layout, handshake sequence diagram, `HandshakeResponder` use case, and error handling for version mismatch in HELLO_ACK.

**Resolution**: specs are the source of truth under SDD. The design's HELLO handshake is deferred to a future change. Task 0.1 reconciles the design document to match the spec before any code is written.

---

## Phase 0 — Reconciliation and Scaffolding

- [ ] 0.1 Reconcile design vs. spec on HELLO handshake: remove §§2.3 `HELLO`/`HELLO_ACK` message types, §2.6 `HELLO` payload, §2.7 `HELLO_ACK` payload, §3.3 Handshake, §4.1 Connection handshake sequence diagram, `HandshakeResponder.swift` and `Handshake.kt` from the module layout, and HELLO-related rows from §6 error handling table. Add a `## Deferred` section noting the HELLO handshake is scoped to a future change. (`transport.md R7`, `wire-protocol.md R2`)

- [ ] 0.2 Initialize git repository and top-level directory structure: `android/`, `macos/`, `protocol/`, `.gitignore` covering Gradle caches, Xcode derived data, and `.DS_Store`. (`design.md §1`)

- [ ] 0.3 Scaffold Android Gradle project: Kotlin 2.x, AGP latest stable, Jetpack Compose BOM, Material 3, `kotlinx-coroutines-android`, JUnit 5 + Turbine for Flow tests, ktlint Gradle plugin. Verify `./gradlew test` passes with one placeholder unit test. (`design.md §1.1`, `android-capture.md R1`)

- [ ] 0.4 Scaffold macOS Xcode project: SwiftUI app target, Swift 5.10+, deployment target macOS 13, XCTest unit-test target wired to `cmd+U`. Verify one placeholder XCTest passes. (`design.md §1.2`, `macos-injection.md R6`)

- [ ] 0.5 Write `protocol/README.md` mirroring `wire-protocol.md` summary and produce binary test vectors as hex files: `protocol/test-vectors/move-with-pressure-tilt.hex` (STYLUS_MOVE, matches R10 worked example exactly), `protocol/test-vectors/proximity-enter.hex` (STYLUS_PROXIMITY entering=1), `protocol/test-vectors/proximity-exit.hex` (STYLUS_PROXIMITY entering=0), `protocol/test-vectors/button-down.hex` (STYLUS_BUTTON primary pressed). Each `.hex` file is a single line of space-separated uppercase byte pairs. (`wire-protocol.md R3–R10`)

- [ ] 0.6 Write `protocol/conformance-checklist.md` listing each wire-protocol requirement (R1–R11) as a checkbox row with columns for Kotlin and Swift implementations. Leave all boxes unchecked — apply fills during Phase 1 tasks. (`wire-protocol.md R1–R11`, `design.md §1.3`)

- [ ] 0.7 Re-run `sdd-init` to enable Strict TDD once both test runners exist (after 0.3 and 0.4). This unlocks the TDD enforcement in sdd-apply for Phases 1–3.

---

## Phase 1 — Wire Protocol Implementation

### 1.1 Kotlin encoder

- [ ] 1.1 Implement `BinaryStylusCodec.kt` encoder in `android/app/src/main/kotlin/dev/inkbridge/android/data/codec/`. Encode all three event types: `STYLUS_MOVE` (36 bytes), `STYLUS_PROXIMITY` (20 bytes), `STYLUS_BUTTON` (20 bytes). Use `java.nio.ByteBuffer` in `LITTLE_ENDIAN` order. Clamp x/y to [0.0, 1.0] before f32 encoding. Map pressure float→u16 per R3 (`round(v × 65535)`). Sequence counter managed by caller. Write unit tests that encode each of the four test vectors from `protocol/test-vectors/` and assert byte-for-byte equality. (`wire-protocol.md R1–R9`, `android-capture.md R2–R3`, `design.md §1.1 data/codec`)

- [ ] 1.2 Implement `BinaryStylusCodec.kt` decoder (round-trip). Decode a `ByteArray` into a structured result: version check (discard if ≠ 1), event_type routing (discard unknown), payload extraction per R6–R8. Write round-trip tests: encode → decode → assert all fields preserved. Write discard tests: unknown event_type, wrong version, buttons field inconsistent with flags. (`wire-protocol.md R2, R4, R8, R9, R11`)

- [ ] 1.3 Implement `BinaryStylusCodec.swift` encoder in `macos/Inkbridge/Transport/Codec/`. Mirror the Kotlin encoder exactly. Use `Data` + manual LE byte writes (no `Foundation` struct packing shortcuts). Write XCTests loading each hex vector from `protocol/test-vectors/` and asserting byte equality. (`wire-protocol.md R1–R9`, `design.md §1.2 Transport/Codec`)

- [ ] 1.4 Implement `BinaryStylusCodec.swift` decoder (round-trip). Version gating, event_type routing, buttons consistency check per R8. Write the same round-trip and discard test suite as 1.2, using the same hex vectors. Tick all Kotlin and Swift columns in `protocol/conformance-checklist.md`. (`wire-protocol.md R2, R4, R8, R9, R11`)

---

## Phase 2 — Android Client

### 2.1 Domain model

- [ ] 2.1 Define domain models in `android/…/domain/model/`: `StylusEvent.kt` (x, y, pressure u16, tilt_x i16, tilt_y i16, buttons byte, phase, timestampNs), `StylusPhase.kt` (enum: HOVER, DOWN, MOVE, UP, PROX_IN, PROX_OUT, BUTTON), `ConnectionState.kt` (sealed: Idle, Connecting, Connected, Error(msg)). Define ports `Transport.kt` (suspend connect/send/close) and `StylusCodec.kt` (encode: StylusEvent → ByteArray). No Android imports in this package. (`design.md §1.1 domain/`, `transport.md R6`, `android-capture.md R1`)

### 2.2 Capture

- [ ] 2.2 Implement `MotionEventMapper.kt` in `data/capture/`. Map `MotionEvent` actions to `StylusPhase`. Filter non-stylus tool types (R1). Normalize x/y (R2). Extract and map pressure (R3). Compute tilt_x/tilt_y from `AXIS_TILT` + `AXIS_ORIENTATION` via `sin/cos × tan(altitude) × 100` (R4). Read button state from `getButtonState()` (R5). Handle ACTION_HOVER_ENTER/MOVE/EXIT (R6). Emit historical samples before current sample (R7). Write unit tests for each scenario in `android-capture.md` R1–R7 using mock MotionEvent values. (`android-capture.md R1–R7`, `design.md §1.1 data/capture`)

### 2.3 Transport

- [ ] 2.3 Implement `UdpTransport.kt`: `DatagramSocket`, `connect()` binds remote address, `send()` writes one datagram per frame, `close()` closes socket. Default port 4545. No auto-reconnect. (`transport.md R1–R3, R6`, `design.md §1.1 data/transport`)

- [ ] 2.4 Implement `TcpTransport.kt`: `Socket` with `TCP_NODELAY = true`, `connect()` with 3-second timeout, blocking `write()` per frame, `close()` on error or user action. Connection on loopback (`127.0.0.1`) only. No auto-reconnect. (`transport.md R1, R4, R6`, `design.md §1.1 data/transport`)

- [ ] 2.5 Implement `StreamStylus.kt` use case: accepts `Flow<StylusEvent>`, calls `StylusCodec.encode()`, writes to `Transport`. Manages sequence counter (starts at 0, increments per frame, wraps at 2^32). (`wire-protocol.md R9`, `design.md §1.1 domain/usecase`)

### 2.4 UI

- [ ] 2.6 Implement `ConnectionViewModel.kt` + `ConnectionScreen.kt`: transport selector (Wi-Fi/UDP default, USB/TCP), host field (hidden when TCP), port field (default 4545, range [1024, 65535]), inline validation on every keystroke, Connect/Disconnect/Cancel buttons, state-driven UI per `ui.md R1–R3, R8`. No persisted settings. (`ui.md R1–R3, R8, R10`, `transport.md R2, R5`, `design.md §3.1–3.2`)

- [ ] 2.7 Implement `CaptureSurface.kt` + `CaptureViewModel.kt`: full-screen `pointerInput` consuming raw `MotionEvent` via `awaitPointerEventScope`, active only in `CONNECTED` state, no local ink rendering, visible affordance (border or background tint). Wire to `MotionEventMapper` → `StreamStylus`. (`ui.md R4`, `android-capture.md R8`, `design.md §1.1 ui/capture`)

- [ ] 2.8 Implement `AndroidManifest.xml` and `InkbridgeApplication.kt`. Register `INTERNET` permission. No other permissions required for this change. Wire DI manually (no Hilt in this change — keep deps minimal for the spike). (`design.md §1.1`)

---

## Phase 3 — macOS Server

### 3.1 Domain model

- [ ] 3.1 Define macOS domain models in `macos/Inkbridge/Domain/`: `StylusEvent.swift`, `StylusPhase.swift`, `InjectionState.swift` (Idle, Listening, Injecting, Error). Define protocols `EventSource.swift` (AsyncStream<StylusEvent>) and `Injector.swift` (inject(_ event: StylusEvent)). No CoreGraphics or Network imports in Domain. (`design.md §1.2 Domain/`, `macos-injection.md R6`)

### 3.2 Transport

- [ ] 3.2 Implement `UdpListener.swift` using `NWListener` on `.udp`, bound to `0.0.0.0:4545`. Each received datagram is decoded via `BinaryStylusCodec.swift`. Apply sequence-number drop policy (discard if seq < last_accepted). Expose as `AsyncStream<StylusEvent>`. (`transport.md R3`, `wire-protocol.md R9`, `design.md §1.2 Transport`)

- [ ] 3.3 Implement `TcpListener.swift` using `NWListener` on `.tcp`, bound to `127.0.0.1:4545`. Accept one client at a time (close existing before accepting new). Frame by reading 16-byte header then payload of length determined by `event_type`. Apply same sequence drop policy. Expose as `AsyncStream<StylusEvent>`. (`transport.md R4`, `wire-protocol.md R3–R4, R9`, `design.md §1.2 Transport`)

### 3.3 Injection

- [ ] 3.4 Implement `AccessibilityGate.swift`: `AXIsProcessTrusted()` check on launch. If denied, block listener start. Poll at ≤ 2-second interval; auto-transition to Listening when granted. Open System Settings URL on button tap. (`macos-injection.md R1`, `ui.md R6–R7`, `design.md §1.2 Injection, §4.3`)

- [ ] 3.5 Implement `CGEventInjector.swift` conforming to `Injector`. For `STYLUS_MOVE` (HOVER=0): create `kCGTabletEventType` event, set PointX/Y (pixels via `CGMainDisplayID`/`CGDisplayBounds`), PointPressure (pressure/65535.0, only when PRESSURE_PRESENT), TiltX/Y (tilt/9000.0, only when TILT_PRESENT), PointButtons. Post mouse-move at same coords after tablet event. For `STYLUS_MOVE` (HOVER=1): same but pressure=0.0. For `STYLUS_PROXIMITY`: create `kCGTabletProximityEventType`, set EnterProximity, PointerType=1, DeviceID=0x0001. Cache display bounds; refresh on `CGDisplayReconfigurationCallback`. On `CGEventPost` failure: log, continue, do NOT close transport. (`macos-injection.md R2–R5, R7–R8`, `design.md §1.2 Injection, ADR-03`)

### 3.4 Use cases and app shell

- [ ] 3.6 Implement `ReceiveAndInject.swift` use case: consume `AsyncStream<StylusEvent>` from the active listener, call `Injector.inject()` synchronously per event. Wire UDP and TCP streams based on which transport the Android client connects on. (`macos-injection.md R7`, `design.md §1.2 Domain/UseCase`)

- [ ] 3.7 Implement macOS UI: `InkbridgeApp.swift` (status-bar + window), `StatusWindow.swift` (four states: IDLE, LISTENING, CONNECTED, ERROR), `PermissionOnboardingView.swift` (accessibility explanation, "Open Accessibility Settings" button), `DiagnosticsView.swift` (rx frame counter, drop counter, bad-type counter). No persisted settings. (`ui.md R5–R9`, `macos-injection.md R1`, `design.md §1.2 Views, §6`)

---

## Phase 4 — Integration and Validation

- [ ] 4.1 End-to-end smoke test over USB (adb reverse): Android connects via TCP to macOS, draw a simple stroke, confirm `CGEventPost` is called with non-zero pressure in Xcode console logs. Document pass/fail in `protocol/conformance-checklist.md`. (`transport.md R4`, `macos-injection.md R2`, `design.md §3.2, §5`)

- [ ] 4.2 End-to-end smoke test over Wi-Fi (UDP): same stroke test, confirm datagrams received and decoded, confirm no crash on out-of-order sequence. (`transport.md R3`, `wire-protocol.md R9`, `design.md §5`)

- [ ] 4.3 Validate pressure + tilt land in at least 2 of: Photoshop, Procreate for Mac, Krita. For each app: open, draw with varying pressure, verify brush modulates. Document per-app results (field accepted / silently ignored / partial) in `protocol/conformance-checklist.md`. (`macos-injection.md R2`, `design.md §8 Risk 1`)

- [ ] 4.4 Measure latency per hop: instrument timestamps at MotionEvent dispatch, encode, send, receive, decode, CGEventPost. Compute P50 and P95 for both USB and Wi-Fi. Compare against budget (P50 ≤ 15 ms USB, P50 ≤ 30 ms Wi-Fi). Document results. (`design.md §5`)

- [ ] 4.5 Write manual QA checklist `protocol/qa-checklist.md` derived from all spec scenarios across `wire-protocol.md`, `transport.md`, `android-capture.md`, `macos-injection.md`, and `ui.md`. Each row: scenario description, expected result, pass/fail column. (`wire-protocol.md R1–R11`, `transport.md R1–R7`, `android-capture.md R1–R9`, `macos-injection.md R1–R8`, `ui.md R1–R10`)
