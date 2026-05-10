# Design: ios-client

> Phase: `sdd-design` | Change: `ios-client` | Date: 2026-05-09

## Approach

A new iOS app target at `ios/InkBridgeIOS.xcodeproj` (iOS 17+, landscape-locked, sideload) ships as a wireless trackpad + Express Keys remote against the existing macOS server. Wire protocol, server, Android, and the codec source-of-truth are untouched. The codec is a one-way COPY of `BinaryStylusCodec.swift` from `macos/`, decode path stripped (iPhone is send-only).

The app is layered (clean architecture): `Domain` (pure structs), `Data` (UserDefaults+Codable settings), `Transport` (split: `NWConnection` for unicast UDP data path, raw BSD sockets for broadcast discovery — `NWConnection` rejects broadcast destinations on iOS), `Protocol` (codec + Mac key codes), `Input` (`TouchRouter` state machine, pure value-type, fully unit-testable), `UI` (SwiftUI shell + a single `UIViewRepresentable` canvas backed by a `UIView` subclass that overrides `touchesBegan/Moved/Ended/Cancelled` — SwiftUI gestures cannot give simultaneous multi-touch with raw timestamps and pointer IDs).

Data flow: `UITouch` events fire on the main thread → translated to a pure `TouchSample` (id, point, timestamp) → `TouchRouter.process(sample)` returns 0..n `StylusEvent`s → `BinaryStylusCodec.encode` produces `Data` → `UDPClient.send(data)` enqueues on `NWConnection` (UDP, unicast). Discovery runs on a `Task` reading `recvfrom` on a BSD socket; results flow as an `AsyncStream<DiscoveredHost>` into the `ConnectionScreen` view model. Lifecycle: `scenePhase == .background` tears down the `NWConnection` and broadcast socket; `.active` re-resolves and reopens.

Latency budget per emitted event: `touchesMoved` → `TouchRouter` ≤ 0.2 ms; encode ≤ 0.1 ms; `NWConnection.send` enqueue ≤ 1 ms; LAN one-way ≤ 5 ms typical; macOS injection ≤ 5 ms (existing). Target: ≤ 50 ms p95 wall-clock from finger movement to cursor injection.

## Architecture

### Module map

```
ios/InkBridgeIOS.xcodeproj
ios/InkBridgeIOS/
├── App/
│   ├── InkBridgeIOSApp.swift            // @main, Scene, ScenePhase wiring
│   ├── AppDelegate.swift                // landscape lock (supportedInterfaceOrientationsFor)
│   └── Info.plist                       // landscape, NSLocalNetworkUsageDescription, NSBonjourServices
├── Domain/
│   ├── StylusEvent.swift                // sum type: cursorDelta/scroll/zoom/button/key/captureRequest
│   ├── ExpressKey.swift                 // keyCode + modifiers + label + holdMode
│   ├── ExpressKeyProfile.swift          // name + [ExpressKey] (6 slots)
│   ├── DiscoveredHost.swift             // ipv4 + port + name + lastSeen
│   ├── ConnectionState.swift            // .idle/.connecting/.connected/.failed
│   └── Settings.swift                   // hostOverride, port, haptics, naturalScroll, sidebarEdge, activeProfileId
├── Data/
│   ├── SettingsRepository.swift         // protocol + UserDefaultsSettingsRepository
│   └── ProfileStore.swift               // JSONEncoder/Decoder over UserDefaults("inkbridge.profiles")
├── Transport/
│   ├── UDPClient.swift                  // protocol UDPClient { func send(_:) async throws }
│   ├── NWConnectionUDPClient.swift      // NWConnection-backed
│   ├── BroadcastDiscovery.swift         // protocol BroadcastDiscovery { func hosts() -> AsyncStream<DiscoveredHost> }
│   ├── BSDBroadcastDiscovery.swift      // socket+SO_BROADCAST+sendto+recvfrom
│   └── ProbeCodec.swift                 // "INKB?" tx + "INKB!1|<port>|<name>" rx parser
├── Protocol/
│   ├── BinaryStylusCodec.swift          // copied from macos/, encode-only (decode removed)
│   └── MacKeyCodes.swift                // human label → CGKeyCode lookup table
├── Input/
│   ├── TouchSample.swift                // pure struct (id, CGPoint, timestamp seconds)
│   ├── TouchRouter.swift                // state machine, see "Touch state machine"
│   ├── GestureGeometry.swift            // helpers (centroid, spread, angle, hysteresis)
│   └── ExpressKeyDispatcher.swift       // ExpressKey → StylusEvent.key sequences
└── UI/
    ├── App/RootView.swift               // routes Connection vs Capture by ConnectionState
    ├── Screens/ConnectionScreen.swift   // discovered hosts list, manual IP, Connect
    ├── Screens/CaptureScreen.swift      // Express Keys sidebar + CanvasRepresentable
    ├── Screens/ExpressKeysSettingsScreen.swift
    ├── Screens/CaptureFromMacModal.swift
    ├── Canvas/CanvasUIView.swift        // UIView subclass (touches* overrides)
    ├── Canvas/CanvasRepresentable.swift // UIViewRepresentable wrapper
    └── ViewModels/                      // @Observable view models
        ├── ConnectionViewModel.swift
        ├── CaptureViewModel.swift
        ├── ExpressKeysViewModel.swift
        └── CaptureFromMacViewModel.swift

ios/InkBridgeIOSTests/
├── Vectors/                             // copies of protocol/test-vectors/*.hex
├── ProtocolTests/BinaryStylusCodecEncodeTests.swift
├── TransportTests/
│   ├── ProbeCodecTests.swift
│   ├── FakeBroadcastDiscoveryTests.swift
│   └── FakeUDPClientTests.swift
├── InputTests/
│   ├── TouchRouterDragTests.swift
│   ├── TouchRouterScrollZoomTests.swift
│   ├── TouchRouterTapTests.swift
│   └── TouchRouterDoubleTapDragTests.swift
├── DataTests/SettingsRepositoryTests.swift
└── DiscoveryTests/DiscoveryFlowTests.swift
```

### Layer responsibilities

- **Domain** — pure Swift, no `Foundation.Network`, no UIKit. `StylusEvent` is a sum type with exactly the 6 emitted variants (`cursorDelta`, `scroll`, `zoom`, `button`, `key`, `captureRequest`). No `move`, no `proximity`.
- **Data** — `SettingsRepository` over `UserDefaults` for primitives; `ProfileStore` Codable-encodes `[ExpressKeyProfile]` into a single JSON blob under `inkbridge.profiles`. UserDefaults survives sideload re-signing with the same bundle ID.
- **Transport** — Two protocols (`UDPClient`, `BroadcastDiscovery`) so unit tests inject fakes. Concrete implementations live in the same layer; nothing else imports `Network` or `Darwin.socket`.
- **Protocol** — `BinaryStylusCodec.encode` only, with a provenance comment pointing at `macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift` and `protocol/README.md`. `MacKeyCodes` is a static lookup `[String: UInt8]` matching the macOS server's accepted codes.
- **Input** — `TouchRouter` is a `struct` with `mutating func process(_ sample: TouchSample) -> [StylusEvent]`. Time comes from an injected closure `now: () -> TimeInterval` so tests run synchronously without sleeps.
- **UI** — `@Observable` view models; SwiftUI screens; a single `UIViewRepresentable` for the canvas. `CanvasUIView` forwards `TouchSample`s to a binding the view model supplies — UIView never knows about `TouchRouter`.

### Sequence: app launch → discovery → connect

```
RootView.task ─► ConnectionVM.start
  ─► BSDBroadcastDiscovery.hosts() opens socket, binds ephemeral port, SO_BROADCAST=1
  ─► every 2 s: sendto("INKB?") to 255.255.255.255:4546 and 192.168.X.255:4546
  ◄── recvfrom unicast "INKB!1|4545|HostName" → ProbeCodec.parse → DiscoveredHost
  ─► AsyncStream yields host → VM appends to @Observable list, prunes >10 s stale
User taps host ─► VM.connect(host) ─► NWConnectionUDPClient.open(host.ipv4, 4545)
  ─► state .connecting → .connected on first .ready → RootView swaps to CaptureScreen
```

### Sequence: touch → packet

```
CanvasUIView.touchesMoved(touches, event)
  ─► for t in touches: emit TouchSample(id: ObjectIdentifier(t), point: t.location, ts: t.timestamp)
  ─► samples → CaptureVM.onSamples (main actor)
  ─► TouchRouter.process(sample) -> [StylusEvent]
  ─► for ev in events: BinaryStylusCodec.encode(ev, flags, seq+=1, mach_absolute_time-derived ns)
  ─► UDPClient.send(data)  (Task, non-blocking; back-pressure dropped silently per protocol)
```

### Sequence: Express Key tap

```
ExpressKeyButton.onTapGesture ─► CaptureVM.tapKey(slot)
  ─► profile.keys[slot] → ExpressKeyDispatcher.events(for:)
  ─► one-shot: [.key(code, mods, .down), .key(code, mods, .up)]
     hold-mode: [.key(code, mods, .down)] on press, [.key(code, mods, .up)] on release
  ─► encode + send (sequence increments per event)
  ─► UIImpactFeedbackGenerator(.medium).impactOccurred()
```

### Sequence: Capture from Mac

```
CaptureFromMacModal.onAppear ─► VM.beginCapture(slot)
  ─► encode .captureRequest(slotId) → send
  ─► open temporary inbound NWConnection.receiveMessage on the SAME local port used for tx
     (NWConnection in UDP mode reads unicast replies bound to its local endpoint)
  ─► on receive: decode using a tiny inline parser (NOT the codec — only 4 bytes need parsing)
     fields: slotId, keyCode, modifiers, cancelled
  ─► VM.applyCaptured(slot, code, mods) → ProfileStore.save → modal dismisses
  Timeout: 10 s → user-visible error, cancel server-side via repeat captureRequest with cancel flag (deferred)
```

### Sequence: background → foreground reconnect

```
ScenePhase .background ─► UDPClient.close, BroadcastDiscovery.cancel
  ◄── ScenePhase .active ─► VM.resume
  ─► if last host known: UDPClient.open(host) directly (no rediscovery wait)
  ─► concurrently: BroadcastDiscovery.hosts() restarts to refresh the picker
```

## Key decisions

| # | Decision | Alternatives | Rationale |
|---|----------|-------------|-----------|
| 1 | Codec is a COPY of `macos/.../BinaryStylusCodec.swift`, encode path only | Shared SPM package; xcframework | Personal spike, send-only client. SPM cross-package adds Xcode workspace + version pinning for one file. Drift mitigated by sharing the same `.hex` test vectors. Provenance comment + matching tests are sufficient. |
| 2 | Discovery uses raw BSD `socket()` + `setsockopt(SO_BROADCAST,1)` + `sendto`/`recvfrom` | `NWConnection` UDP; `NWBrowser` Bonjour | `NWConnection` fails immediately on broadcast destinations on iOS (engram #220). Bonjour requires server-side `NWListener.service` we don't run for the data path. BSD matches Android's `DatagramSocket(broadcast=true)` and macOS `BroadcastResponder`. |
| 3 | Data path uses `NWConnection` with `NWParameters.udp` | Raw socket for everything | `NWConnection` gives Apple's automatic Wi-Fi Assist suspend/resume + connection state KVO, which BSD does not. Unicast sends work fine. Splitting transports is the cleanest seam. |
| 4 | Capture-from-Mac response read via temporary inbound `NWConnection.receiveMessage` on the same local port used for tx | Listen continuously on a separate `NWListener`; reuse BSD socket | `NWListener` would force a permanent inbound socket and second permission cycle. Reusing tx port keeps NAT/router pinholes warm and avoids a second socket. The capture decode is 4 bytes — inline parsing, not the codec. |
| 5 | Touch capture is a `UIView` subclass wrapped in `UIViewRepresentable`; SwiftUI gestures used elsewhere | All-SwiftUI `DragGesture`/`SimultaneousGesture`; `SpatialTapGesture` for double-tap-drag | SwiftUI gestures cannot expose simultaneous per-finger raw positions with timestamps + stable IDs; double-tap-drag's 350 ms window needs `UITouch.timestamp` precision. Mirrors Android's `pointerInteropFilter` + raw `MotionEvent` pattern. Engram #223. |
| 6 | View models use `@Observable` (iOS 17 Observation framework) | `ObservableObject` + `@Published` | iOS 17+ minimum. Observation has lower overhead, no `objectWillChange` boilerplate, and integrates naturally with the new SwiftUI tracking. |
| 7 | Persistence: `UserDefaults` for primitives, JSON-encoded `[ExpressKeyProfile]` blob under one key | SwiftData; CoreData; file in Documents/ | Total payload ≤ a few KB. SwiftData/CoreData are heavyweight and add migration risk on sideload reinstall. UserDefaults survives reinstall with same bundle ID. |
| 8 | Concurrency: Swift concurrency throughout — `Task`, `async/await`, `AsyncStream` for discovery firehose; `@MainActor` on all view models; `TouchRouter` is non-actor (called from main only) | GCD + completion handlers; Combine | Touch firehose is main-thread by definition. `NWConnection` exposes async send via continuation. `AsyncStream` is the correct abstraction for the discovery channel. No `Combine` to keep the dependency graph minimal. |
| 9 | Local Network permission: `NSLocalNetworkUsageDescription` + `NSBonjourServices=["_inkbridge._udp"]` even though we don't browse Bonjour | Description string only | Without `NSBonjourServices`, the prompt may not fire reliably for raw socket use; the broadcast `sendto` then silently fails the first run. Engram #221. |
| 10 | Test runner: `xcodebuild test` with split `build-for-testing` + `test-without-building`; broadcast tested via `BroadcastDiscovery` protocol fake; `NWConnection` tested via `UDPClient` protocol fake | Real socket integration tests in CI | Simulator cannot send/receive 255.255.255.255 from the host machine reliably; CI here is local-only. Protocol seams make unit tests deterministic and fast. |

## Touch state machine (TouchRouter)

States:

- `idle` — no fingers down.
- `oneFingerActive(id, lastPoint, downAt, downPoint, hasMovedBeyondTapSlop)` — exactly one finger.
- `twoFingerEvaluating(ids, startCentroid, startSpread, startedAt)` — 2nd finger landed; deciding scroll vs zoom.
- `twoFingerScroll(ids, lastCentroid)` — translation-dominant locked.
- `twoFingerZoom(ids, lastSpread)` — spread-dominant locked.
- `doubleTapDragArmed(downAt, downPoint, firstTapEndedAt, firstTapEndPoint)` — first tap ended ≤ 350 ms ago, awaiting second touchDown.
- `doubleTapDragActive(id, lastPoint)` — second touchDown happened inside window + spatial tolerance; subsequent moves emit `cursorDelta` AND a virtual `button(left=down)` was sent on entry; `button(left=up)` on touch end.

Constants (parameterized for tests):

- `tapMaxDuration = 250 ms`
- `tapMaxSlop = 10 pt`
- `doubleTapWindow = 350 ms`
- `doubleTapSpatialTolerance = 20 pt`
- `scrollZoomEvaluationWindow = 60 ms` after 2nd finger touchDown
- `scrollZoomLockHysteresis = 1.5x` (translation-dominant if `|Δcentroid| > 1.5 * |Δspread|`, else zoom)
- `cursorAccelerationCurve = identity` v1 (linear)

Transitions (touch event in → state'/emitted events out):

```
idle + touchDown(id)                              → oneFingerActive(id, p, now, p, false)         emits []
oneFingerActive + touchMoved(id, p)               → oneFingerActive(id, p, …, hasMoved=true if>slop)
                                                    if hasMoved: emit [.cursorDelta(dx, dy)] (in absolute Int16 pt)
oneFingerActive + touchUp(id)
   if !hasMoved && now-downAt<=tapMaxDuration:    → doubleTapDragArmed(now, downPoint, now, p)    emits [.button(LEFT_DOWN), .button(LEFT_UP)]  (left-click)
   else                                            → idle                                          emits []
oneFingerActive + touchDown(id2)                  → twoFingerEvaluating([id,id2], centroid, spread, now)   emits []
twoFingerEvaluating + touchMoved within window
   if Δcentroid > 1.5*Δspread: lock scroll        → twoFingerScroll                                emits [.scroll(dx,dy)]
   else if Δspread > 1.5*Δcentroid: lock zoom     → twoFingerZoom                                  emits [.zoom(scaleDelta)]
twoFingerEvaluating + both touchUp inside tap window  → idle                                       emits [.button(RIGHT_DOWN), .button(RIGHT_UP)]  (right-click)
twoFingerScroll + move                            → twoFingerScroll                                emits [.scroll(dx,dy)]
twoFingerZoom + move                              → twoFingerZoom                                  emits [.zoom(scaleDelta)]
twoFinger* + any touchUp                          → idle (drop the other finger via touchCancelled if needed)  emits []
doubleTapDragArmed + touchDown(id3) within 350 ms AND |p3 - firstTapEndPoint| ≤ 20 pt
                                                  → doubleTapDragActive(id3, p3)                   emits [.button(LEFT_DOWN)]
doubleTapDragArmed + 350 ms elapsed (timer poke)  → idle                                          emits []
doubleTapDragActive + touchMoved                  → doubleTapDragActive(id, p')                    emits [.cursorDelta(dx,dy)]
doubleTapDragActive + touchUp                     → idle                                          emits [.button(LEFT_UP)]
any state + touchCancelled (system gesture)       → idle                                          emits [.button(*_UP) for any held buttons]
3+ fingers                                        → idle (cancel current gesture)                 emits []
```

Cursor delta encoding: `(point.x - lastPoint.x, point.y - lastPoint.y)` in points, rounded to `Int16`, clamped to ±32767. Server scaling factor is configured server-side.

The "timer poke" for `doubleTapDragArmed` is implemented by passing the current timestamp into every `process()` call — when no event arrives, the canvas calls `process(empty: now)` on a `CADisplayLink` tick (60 Hz). This avoids real timers in tests; tests advance time by passing crafted timestamps.

## Express Keys data model

```swift
public struct ExpressKey: Codable, Equatable, Identifiable {
    public let id: UUID
    public var label: String          // shown on the button face
    public var keyCode: UInt8         // server-side key code (see MacKeyCodes)
    public var modifiers: UInt8       // bitmask: SHIFT=1, CTRL=2, ALT=4, CMD=8
    public var holdMode: HoldMode     // .oneShot or .modifierHold
}
public enum HoldMode: String, Codable { case oneShot, modifierHold }

public struct ExpressKeyProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var keys: [ExpressKey]     // exactly 6, slot order = display order
}
```

`ProfileStore` JSON schema (UserDefaults key `inkbridge.profiles`):

```json
{ "version": 1,
  "activeProfileId": "UUID",
  "profiles": [ { "id": "UUID", "name": "Photoshop", "keys": [ { "id":"UUID","label":"Undo","keyCode":6,"modifiers":8,"holdMode":"oneShot" }, ... ] } ] }
```

A schema `version: 1` field anchors future migrations. Fail-closed: if decoding fails, fall back to a single built-in default profile and log.

## Latency budget

| Hop | Budget (p95) | Source |
|-----|--------------|--------|
| `touchesMoved` callback queued → `TouchRouter.process` | ≤ 0.5 ms | UIKit + struct method |
| `process` → `[StylusEvent]` | ≤ 0.2 ms | pure CPU |
| `BinaryStylusCodec.encode` | ≤ 0.1 ms | byte writes |
| `NWConnection.send` enqueue | ≤ 1 ms | async continuation |
| LAN one-way (Wi-Fi 5/6) | 2–5 ms | network |
| macOS `CGEvent` injection | ≤ 5 ms | existing |
| **Total finger → cursor** | **≤ 50 ms p95** | sum + jitter |

If `NWConnection.send` falls behind, packets are dropped at the iOS network stack with no app-level back-pressure (UDP is fire-and-forget). Each `StylusEvent` carries an independent monotonic `sequence`.

## Strict-TDD test strategy

| Module | Test class | Mocks/stubs | Representative cases |
|--------|-----------|-------------|----------------------|
| `BinaryStylusCodec` | `BinaryStylusCodecEncodeTests` | none — pure | (a) `cursorDelta(10,-3)` matches `cursor_delta_basic.hex`; (b) `key(0x06, CMD, .down)` matches `key_event_undo.hex`; (c) clamping `Int16.max+1` |
| `ProbeCodec` | `ProbeCodecTests` | none | (a) parse `INKB!1\|4545\|MacBook` → host; (b) reject `BAD!`; (c) tolerate hostnames with spaces |
| `BSDBroadcastDiscovery` | `DiscoveryFlowTests` (uses `FakeBroadcastDiscovery` conforming to protocol) | injected fake `BroadcastDiscovery` | (a) yields hosts from injected stream; (b) prunes after 10 s; (c) deduplicates by IP |
| `NWConnectionUDPClient` | exercised indirectly through `FakeUDPClient` in VM tests; smoke test on simulator | none | smoke only |
| `TouchRouter` | `TouchRouterDragTests`, `…ScrollZoomTests`, `…TapTests`, `…DoubleTapDragTests` | injected `now` clock | (a) 1f drag emits ordered `cursorDelta`s; (b) 2f translate locks scroll past hysteresis; (c) tap inside 250 ms emits left-click; (d) double-tap-drag inside 350 ms + 20 pt enters drag; (e) `touchCancelled` releases held buttons |
| `SettingsRepository` | `SettingsRepositoryTests` | suite-isolated `UserDefaults(suiteName:)` | (a) round-trip primitives; (b) profile list survives encode/decode; (c) corrupted blob falls back to default |
| `ExpressKeyDispatcher` | `ExpressKeyDispatcherTests` | none | (a) one-shot emits down+up; (b) hold-mode emits down on press, up on release |
| `ConnectionViewModel` | `ConnectionViewModelTests` | `FakeBroadcastDiscovery`, `FakeUDPClient` | (a) tap host triggers `connect`; (b) failed connect surfaces error; (c) backgrounding closes client |
| `CaptureViewModel` | `CaptureViewModelTests` | `FakeUDPClient`, fake `TouchRouter` events | (a) sample stream produces send calls in order; (b) Express Key tap sends KEY_DOWN+KEY_UP |

Each test file is RED → GREEN → REFACTOR. The test target is created in the very first apply batch (before any production code) so the simulator boot cost is paid once and `xcodebuild test-without-building` can re-run subsequent iterations fast.

## Risks & mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Local Network permission re-prompts every 7 days on sideload | High | Banner in `ConnectionScreen` explains; manual-IP entry stays first-class. Not fixable without paid Developer account. |
| Wi-Fi router blocks broadcast (guest/enterprise/AP isolation) | Medium | Manual-IP fallback; empty-state CTA. No USB on iOS. |
| BSD socket code is platform-fragile in the simulator | Medium | Discovery hidden behind `BroadcastDiscovery` protocol; unit tests use a fake, not a real socket. Real-socket smoke test gated `// requires device`. |
| Double-tap-drag 350 ms window racey on slow devices | Low | All time comes from `UITouch.timestamp` (not gesture recognizer delay); window is parameterized; tests cover the boundary at 349/350/351 ms and 19/20/21 pt. |
| Codec drift between `macos/` and `ios/` copies | Low | Both must pass the same `protocol/test-vectors/*.hex`. Vectors copied into `ios/InkBridgeIOSTests/Vectors/` and asserted byte-for-byte. |
| `xcodebuild test` simulator boot is slow | Low | First batch creates the test target; thereafter `build-for-testing` once + repeated `test-without-building`. |
| Capture-from-Mac response receive on the tx port is undocumented behavior | Low | If `NWConnection.receiveMessage` fails to deliver inbound replies bound to the local endpoint, fall back to a temporary `NWListener` for the duration of the modal. Decided at apply time after a smoke test. |

## Out of scope (deferred)

- Stylus capture (no Pencil on iPhone — will not emit `STYLUS_MOVE`/`STYLUS_PROXIMITY`).
- USB transport (no `adb reverse` equivalent inside the iOS sandbox).
- iPad layout (deferred — different breakpoints, possible Apple Pencil support, separate change).
- App Store distribution; CI for iOS; release versioning.
- Background mode UDP; arbitrary background socket retention.
- mDNS/Bonjour discovery for the data path — `NSBonjourServices` is only the permission-trigger.
- Pressure-curves UI (no pressure on iPhone).
- Latency histogram / debug HUD.
- Shared SPM package for codec across `macos/` and `ios/`.
- Any change to `macos/`, `android/`, `protocol/README.md`, `protocol/test-vectors/`.
