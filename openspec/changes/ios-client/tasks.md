# Tasks: ios-client

> Phase: `sdd-tasks` | Change: `ios-client` | Strict TDD: ACTIVE | Date: 2026-05-09

---

## Block 0 — Project Bootstrap

- [ ] 0.1 [setup] Create `ios/` directory. In Xcode: new project → App, product name `InkBridgeIOS`, bundle ID `com.inkbridge.ios`, Swift/SwiftUI, iOS 17.0 deployment target. Add `InkBridgeIOSTests` unit test target. Save as `ios/InkBridgeIOS.xcodeproj`.
- [x] 0.2 [setup] Configure `ios/InkBridgeIOS/App/Info.plist`: `NSLocalNetworkUsageDescription`, `NSBonjourServices = ["_inkbridge._udp"]`, `UISupportedInterfaceOrientations = [UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]`, `UIStatusBarHidden = YES`, `UIHomeIndicatorAutoHidden = YES`.
- [x] 0.3 [setup] Create `ios/InkBridgeIOSTests/Vectors/`. Copy all `protocol/test-vectors/*.hex` into it. Add a `Copy Files` build phase (Resources) or a manual README note documenting this copy step — matching the pattern in `protocol/README.md`.
- [x] 0.4 [setup] Add `Makefile` targets at repo root: `ios-test` → `xcodebuild test -scheme InkBridgeIOS -destination 'platform=iOS Simulator,name=iPhone 15' -quiet`; `ios-build-for-testing` → `xcodebuild build-for-testing …`; `ios-test-without-building` → `xcodebuild test-without-building …`. Document in `Makefile` comment.

---

## Block A — Domain Types (pure Swift, no Network / UIKit)

- [x] A.1 [test] `InkBridgeIOSTests/DomainTests/StylusEventTests.swift` — test all 6 sum-type variants (`cursorDelta`, `scroll`, `zoom`, `button`, `key`, `captureRequest`): equality, exhaustive switch compiles (no `default`), no `move` or `proximity` variants present.
- [x] A.2 [impl] `ios/InkBridgeIOS/Domain/StylusEvent.swift` — Swift `enum StylusEvent` with associated values for the 6 types only.
- [x] A.3 [test] `InkBridgeIOSTests/DomainTests/ExpressKeyTests.swift` — `ExpressKey` equality + Codable round-trip; `HoldMode` raw values `.oneShot` / `.modifierHold`; modifier bitmask constants (SHIFT=1, CTRL=2, ALT=4, CMD=8).
- [x] A.4 [impl] `ios/InkBridgeIOS/Domain/ExpressKey.swift`, `ExpressKeyProfile.swift` — `Codable`, `Equatable`, `Identifiable`; exactly 6 slots per profile (per design.md §Express Keys data model).
- [x] A.5 [test] `InkBridgeIOSTests/DomainTests/DiscoveredHostTests.swift` — `DiscoveredHost` equality; staleness check: `lastSeen` older than 10 s returns `isStale == true`.
- [x] A.6 [impl] `ios/InkBridgeIOS/Domain/DiscoveredHost.swift`, `ConnectionState.swift` (`.idle/.connecting/.connected/.failed`), `Settings.swift`.

---

## Block B — Protocol Codec (encode-only)

- [x] B.1 [test] `InkBridgeIOSTests/ProtocolTests/BinaryStylusCodecEncodeTests.swift` — encode `cursorDelta(10, -3)` must match `cursor-delta-basic.hex` vector byte-for-byte. (Author vector if absent — see Block 0.3 and `protocol/README.md`.)
- [x] B.2 [impl] `ios/InkBridgeIOS/Protocol/BinaryStylusCodec.swift` — COPY from `macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift`, remove decode path, add provenance comment pointing at source file and `protocol/README.md`.
- [x] B.3 [test] Round-trip vectors for `STYLUS_BUTTON (0x03)`, `STYLUS_SCROLL (0x04)`, `STYLUS_ZOOM (0x05)`, `KEY_EVENT (0x07)`, `CAPTURE_REQUEST (0x08)` — one test case per event type, each against its `.hex` vector.
- [x] B.4 [impl] Fill in any remaining encoder cases revealed by B.3 failures.
- [x] B.5 [test] `SequenceCounterTests.swift` — wraps at `UInt32.max + 1 → 0`; monotonically increases under concurrent increments (use `DispatchGroup` or `Task` groups × 100 iterations).
- [x] B.6 [impl] `ios/InkBridgeIOS/Protocol/SequenceCounter.swift` — atomic `UInt32` increment with wrap.
- [x] B.7 [impl] `ios/InkBridgeIOS/Protocol/MacKeyCodes.swift` — static `[String: UInt8]` lookup table, ported from `android/` kVK_* mapping.

---

## Block C — Transport: Data Path (NWConnection)

- [x] C.1 [test] `InkBridgeIOSTests/TransportTests/UDPClientTests.swift` — define `FakeUDPClient` conforming to `UDPClient` protocol; assert `send(_:)` queues bytes in order; assert calling `send` while disconnected throws `UDPClientError.notConnected`.
- [x] C.2 [impl] `ios/InkBridgeIOS/Transport/UDPClient.swift` (protocol) + `ios/InkBridgeIOS/Transport/NWConnectionUDPClient.swift` — `NWParameters.udp` unicast; `async send` via continuation; connection state published via `@Observable`.
- [x] C.3 [test] Lifecycle tests: `connect → disconnect → connect` sequence; assert state transitions `.idle → .connecting → .connected → .idle → .connecting`; assert no send after explicit disconnect throws.
- [x] C.4 [impl] `NWConnectionUDPClient` state management; exponential backoff sequence 0.5/1/2/5 s on transient failure (per spec §Reconnection); `close()` sets state `.idle`.

---

## Block D — Transport: Discovery (BSD Sockets)

- [x] D.1 [test] `InkBridgeIOSTests/TransportTests/BroadcastDiscoveryTests.swift` — inject a `FakeBroadcastDiscovery` conforming to `BroadcastDiscovery` protocol; emit two fake `DiscoveredHost` values via `AsyncStream`; assert both appear in the collected output.
- [x] D.2 [impl] `ios/InkBridgeIOS/Transport/BroadcastDiscovery.swift` (protocol `{ func hosts() -> AsyncStream<DiscoveredHost> }`) + `ios/InkBridgeIOS/Transport/BSDBroadcastDiscovery.swift` — `socket(AF_INET, SOCK_DGRAM, 0)` + `setsockopt(SO_BROADCAST, 1)` + `sendto(255.255.255.255:4546)` probe every 2 s on a `Task`; `recvfrom` loop parses `ProbeCodec` response.
- [x] D.3 [test] `ProbeCodecTests.swift` — parse `"INKB!1|4545|MacBook Pro"` → valid `DiscoveredHost`; reject `"BAD!"` → `nil`; tolerate hostnames with spaces or hyphens.
- [x] D.4 [impl] `ios/InkBridgeIOS/Transport/ProbeCodec.swift` — `"INKB?"` tx payload; `"INKB!<version>|<port>|<name>"` rx parser.
- [x] D.5 [test] `DiscoveryFlowTests.swift` — stale host: emit host, advance fake `lastSeen` clock by 11 s, assert host removed from stream; dedup: emit same IP twice, assert only one entry in list; probe interval covered via HostRegistryTests.swift (injected-clock boundary tests).
- [x] D.6 [impl] `ios/InkBridgeIOS/Transport/HostRegistry.swift` — `actor`-isolated dedup by IP + staleness sweep every 2 s; prunes entries older than `DISCOVERY_STALE_PRUNE_S = 10 s`.

---

## Block E — Input: TouchRouter State Machine (HIGH RISK)

- [x] E.1 [test] `InkBridgeIOSTests/InputTests/TouchRouterTapTests.swift` — 1-finger tap (< 250 ms, < 10 pt slop) emits `[.button(LEFT_DOWN), .button(LEFT_UP)]`; drag (> 10 pt) emits no button events; `touchCancelled` on held state emits button-up for any open button.
- [x] E.2 [impl] `ios/InkBridgeIOS/Input/TouchSample.swift` (pure struct: id, CGPoint, timestamp) + `ios/InkBridgeIOS/Input/TouchRouter.swift` — `struct` with `mutating func process(_ sample: TouchSample) -> [StylusEvent]`; injected `now: () -> TimeInterval`; all 7 states from design.md §Touch state machine.
- [x] E.3 [test] `TouchRouterDragTests.swift` — 1-finger drag emits `cursorDelta(dx, dy)` with correct deltas; clamped at ±32767 (`Int16` max); cursor acceleration is identity (v1).
- [x] E.4 [impl] `ios/InkBridgeIOS/Input/GestureGeometry.swift` — centroid, spread, distance helpers used by `TouchRouter`.
- [x] E.5 [test] `TouchRouterTimingTests.swift` — double-tap-drag: second touch at 349 ms → enters `doubleTapDragActive`; at 350 ms → also enters (boundary inclusive per spec); at 351 ms → treated as new tap. Use injected clock, no real timers.
- [x] E.6 [impl] Wire `CADisplayLink`-based `process(empty: now)` poke for `doubleTapDragArmed` timeout (canvas layer only, not in the struct itself — struct stays pure).
- [x] E.7 [test] `TouchRouterSpatialTests.swift` — spatial tolerance: second touch at 19 pt → drag; at 20 pt → drag (boundary inclusive); at 21 pt → new tap. Boundary tests also at 9/10/11 pt for `tapMaxSlop`.
- [x] E.8 [test] `TouchRouterScrollZoomTests.swift` — 2-finger translate-dominant (|Δcentroid| > 1.5×|Δspread|) → `scroll`; spread-dominant → `zoom`; hysteresis: once locked to scroll, subsequent spread does NOT switch to zoom; 2-finger tap (< tap window, < 10 pt slop) → `[.button(RIGHT_DOWN), .button(RIGHT_UP)]`.
- [x] E.9 [impl] `twoFingerEvaluating`, `twoFingerScroll`, `twoFingerZoom` state logic + `doubleTapDragArmed`/`Active` transitions (per design.md transition table).

---

## Block F — Capture Canvas (UIView + UIViewRepresentable)

- [x] F.1 [note] No unit tests possible for raw `UIView` touch overrides (requires device/XCUITest). Document this in `InkBridgeIOSTests/InputTests/README.md` (one-liner).
- [x] F.2 [impl] `ios/InkBridgeIOS/UI/Canvas/CanvasUIView.swift` — `UIView` subclass; `touchesBegan/Moved/Ended/Cancelled` → emit `TouchSample` to an injected `TouchEventSink` protocol. Zero business logic; pure adapter (per design.md §Layer responsibilities).
- [x] F.3 [impl] `ios/InkBridgeIOS/UI/Canvas/CanvasRepresentable.swift` — `UIViewRepresentable` wrapping `CanvasUIView`; wires `TouchEventSink` to the view model binding.
- [x] F.4 [impl] `ios/InkBridgeIOS/UI/Screens/CaptureScreen.swift` — SwiftUI fullscreen shell: `CanvasRepresentable`, Express Keys sidebar (chosen edge), connection-state pill, settings button, disconnect button; `.defersSystemGestures(.bottom)`, `.persistentSystemOverlays(.hidden)`, `.statusBarHidden(true)` (per spec §Edge-Swipe Suppression).

---

## Block G — Express Keys

- [x] G.1 [test] `InkBridgeIOSTests/InputTests/ExpressKeyDispatcherTests.swift` — one-shot: tap emits `[.key(code, mods, .down), .key(code, mods, .up)]`; modifier-hold: press emits `[.key(…, .down)]`, release emits `[.key(…, .up)]`; unassigned slot emits `[]`.
- [x] G.2 [impl] `ios/InkBridgeIOS/Input/ExpressKeyDispatcher.swift` — pure function `events(for:, phase:) -> [StylusEvent]`.
- [x] G.3 [impl] `ios/InkBridgeIOS/UI/Canvas/ExpressKeysSidebar.swift` — vertical 6-button stack; label from `ExpressKey.label`; `UIImpactFeedbackGenerator(.medium)` on tap; edge toggled via `Settings.sidebarEdge`.
- [x] G.4 [test] `InkBridgeIOSTests/DataTests/ProfileStoreTests.swift` — round-trip `[ExpressKeyProfile]` through `ProfileStore` using a suite-isolated `UserDefaults(suiteName:)`; corrupted blob falls back to built-in default; schema `version: 1` field present in serialized JSON.
- [x] G.5 [impl] `ios/InkBridgeIOS/Data/ProfileStore.swift` — `JSONEncoder/Decoder` over `UserDefaults("inkbridge.profiles")`; fail-closed to default profile on decode error.
- [x] G.6 [test] `InkBridgeIOSTests/DataTests/SettingsRepositoryTests.swift` — round-trip `hostOverride`, `port`, `haptics`, `naturalScroll`, `sidebarEdge`, `activeProfileId` via suite-isolated `UserDefaults`.
- [x] G.7 [impl] `ios/InkBridgeIOS/Data/SettingsRepository.swift` — protocol + `UserDefaultsSettingsRepository`; `@Observable`.
- [x] G.8 [impl] `ios/InkBridgeIOS/UI/Screens/ExpressKeysSettingsScreen.swift` — profile picker (create/rename/delete) + per-slot edit sheet.
- [x] G.9 [impl] `ios/InkBridgeIOS/UI/Screens/EditKeySheet.swift` — preset picker + "Capture from Mac" button entry point.

---

## Block H — Capture from Mac

- [x] H.1 [test] `InkBridgeIOSTests/TransportTests/CaptureResponseParserTests.swift` — parse 4-byte inline response: valid `(slotId, keyCode, modifiers, cancelled=0)` → `CaptureResult.captured`; `cancelled=1` → `CaptureResult.cancelled`; malformed (< 4 bytes) → `CaptureResult.malformed`.
- [x] H.2 [impl] `ios/InkBridgeIOS/Transport/CaptureResponseParser.swift` — inline 4-byte parser (NOT via codec per design.md §Key decision 4).
- [x] H.3 [impl] `ios/InkBridgeIOS/Transport/CaptureResponseListener.swift` — `NWConnection.receiveMessage` on the same local port used for tx; 10 s timeout; fallback to temporary `NWListener` if inbound delivery fails (decided at apply time per design.md §Risks).
- [x] H.4 [impl] `ios/InkBridgeIOS/UI/Screens/CaptureFromMacModal.swift` — opens, sends `captureRequest(slotId)`, awaits response, assigns to slot, dismisses. Cancel button closes without modifying slot.
- [x] H.5 [impl] `ios/InkBridgeIOS/UI/ViewModels/CaptureFromMacViewModel.swift` — `@Observable`; orchestrates `CaptureResponseListener` + `ProfileStore` update.

---

## Block I — Connection Screen + ViewModels

- [x] I.1 [test] `InkBridgeIOSTests/TransportTests/ConnectionViewModelTests.swift` — with `FakeBroadcastDiscovery` + `FakeUDPClient`: tap discovered host populates field and triggers connect; manual IP connect sends to entered IP; background scene phase closes `FakeUDPClient`.
- [x] I.2 [impl] `ios/InkBridgeIOS/UI/ViewModels/ConnectionViewModel.swift` — `@Observable`; orchestrates `BroadcastDiscovery` stream, `UDPClient.connect`, `SettingsRepository` persist; exposes `connectionState`, `discoveredHosts`, `hostField`.
- [x] I.3 [test] `InkBridgeIOSTests/TransportTests/CaptureViewModelTests.swift` — `FakeUDPClient` + injected `TouchRouter` events: sample stream produces `send` calls in order; Express Key tap sends KEY_DOWN + KEY_UP via `FakeUDPClient`.
- [x] I.4 [impl] `ios/InkBridgeIOS/UI/ViewModels/CaptureViewModel.swift` — `@MainActor`, `@Observable`; owns `TouchRouter` instance; calls `BinaryStylusCodec.encode` + `UDPClient.send`.
- [x] I.5 [impl] `ios/InkBridgeIOS/UI/Screens/ConnectionScreen.swift` — discovered-hosts list (Wi-Fi tab only; no USB tab); manual IP + port form below; Local Network permission-denied banner with link to Settings (per spec §Permission denied fallback).
- [x] I.6 [impl] `ios/InkBridgeIOS/UI/App/RootView.swift` — routes `ConnectionScreen` vs `CaptureScreen` based on `ConnectionState`; wires `@Environment(\.scenePhase)` for lifecycle.

---

## Block J — Lifecycle

- [ ] J.1 [test] `InkBridgeIOSTests/LifecycleTests/ReconnectOnForegroundTests.swift` — inject fake `ScenePhase` sequence: `.active → .background → .active`; assert `FakeUDPClient.closeCallCount == 1` after background; assert reconnect attempt within 1 s after foreground (use injected clock, no real timers).
- [ ] J.2 [impl] `ios/InkBridgeIOS/App/InkBridgeIOSApp.swift` — `@main`; `@Environment(\.scenePhase)` → `.background`: `UDPClient.close`, discovery cancel; `.active` after background: `ConnectionViewModel.resume()` using cached last host (per spec §Foreground auto-reconnects).
- [ ] J.3 [impl] `ios/InkBridgeIOS/App/AppDelegate.swift` — `supportedInterfaceOrientationsFor` returns `.landscape` only (landscape lock per project standard).

---

## Block K — Polish

- [ ] K.1 [impl] Connection-state pill in `CaptureScreen` — `.idle` gray / `.connecting` yellow / `.connected` green / `.failed` red + host:port label while connected (per spec §Connection State).
- [ ] K.2 [impl] Click-flash visual feedback on canvas tap (brief overlay highlight on `STYLUS_BUTTON` emit — parity with Android).
- [ ] K.3 [impl] App icon: add 1024×1024 placeholder PNG to `ios/InkBridgeIOS/Assets.xcassets/AppIcon.appiconset/`.

---

## Block L — Protocol README Gap Fix

- [x] L.1 [docs] Update `protocol/README.md`: add `CAPTURE_REQUEST (0x08)` to the event-type table (currently ends at `KEY_EVENT 0x07` — gap flagged in spec phase). Cross-reference with project README. (Done in Batch 2 alongside L.2 — table, payload section, and vectors table all updated.)
- [x] L.2 [docs] Add `capture-request.hex` test vector to `protocol/test-vectors/` if absent; copy into `ios/InkBridgeIOSTests/Vectors/` and add a corresponding test case in Block B.3.

---

## Block M — Manual Smoke Tests (no automation)

- [ ] M.1 [manual] Build to physical iPhone via Xcode + free Apple ID. Confirm Local Network permission prompt appears on first LAN packet.
- [ ] M.2 [manual] Discover Mac on same Wi-Fi → tap host → connect → 1-finger drag moves cursor on Mac.
- [ ] M.3 [manual] 2-finger scroll and pinch-zoom in a Mac app; confirm correct events fired (no cross-contamination).
- [ ] M.4 [manual] Double-tap-drag selects text in a Mac text editor.
- [ ] M.5 [manual] Express Key shortcuts fire correctly; profile switch persists after backgrounding.
- [ ] M.6 [manual] Capture-from-Mac round-trip: modal opens → press key on Mac → slot updates → modal dismisses.
- [ ] M.7 [manual] Background → foreground → connection re-established within 1 s.
- [ ] M.8 [manual] Note in README: sideload cert expires in 7 days; re-sign with Xcode (same bundle ID preserves UserDefaults).
