# Proposal: iOS Client (iPhone)

> Phase: `sdd-propose` | Change: `ios-client` | Date: 2026-05-09

## Intent

Add an iPhone client to InkBridge as a wireless trackpad + Express Keys remote for the
existing macOS server. This is **NOT** a drawing tablet: the iPhone has no Apple Pencil,
no pressure sensor, and no stylus protocol. The value prop is "use the phone in your pocket
as a Magic Trackpad with a programmable shortcut sidebar" — closing the third-client gap
(Android + macOS server already exist) without touching the wire protocol or the server.

## Background

InkBridge ships an Android client (Kotlin + Compose) that captures S Pen strokes and finger
gestures, plus a macOS server (Swift, `InkBridgeCore` SPM package) that injects events via
CoreGraphics. The wire protocol (`protocol/README.md`) is binary, little-endian, with a fixed
16-byte header — already documented and stable. The macOS `BroadcastResponder` listens on
UDP `:4546` for `INKB?` probes; Android replies via `BroadcastDiscoveryRepository`.

Adding iOS now lets users with a personal Apple ID sideload a working trackpad without
running Magic Trackpad over Bluetooth or installing third-party kernel extensions. The
iPhone form factor differs from iPad: smaller canvas, no Pencil, landscape-only — so we
ship iPhone-only in this change and defer iPad to a later one.

## Scope

### In Scope
- New iOS app target at `ios/InkBridgeIOS.xcodeproj`, iOS 17+, landscape-locked.
- Wi-Fi UDP transport: `NWConnection` for unicast event sending; raw BSD sockets for the
  broadcast discovery probe (`NWConnection` cannot set `SO_BROADCAST`).
- Custom UDP discovery probe to `:4546` mirroring Android's behavior (probes `255.255.255.255`
  and subnet directed broadcasts every 2 s; 10 s stale-prune).
- `BinaryStylusCodec.swift` copied from `macos/` — encode-only on iOS (client is send-only),
  with decode path stripped.
- `UIViewRepresentable` canvas with raw `UITouch` (`touchesBegan/Moved/Ended/Cancelled`) —
  SwiftUI gestures cannot deliver simultaneous multi-touch with the precision needed for
  the 350 ms double-tap-drag window or pinch-vs-scroll disambiguation.
- Touch routing state machine: 1f drag → `CURSOR_DELTA (0x06)`, 1f tap → `STYLUS_BUTTON (0x03)`,
  2f drag → `STYLUS_SCROLL (0x04)` or `STYLUS_ZOOM (0x05)` with hysteresis, 2f tap → right-click,
  double-tap-drag (350 ms) → drag-select.
- Express Keys sidebar (6 buttons), profiles persisted as JSON in `UserDefaults` via `Codable`.
- Capture-from-Mac flow (`CAPTURE_REQUEST 0x08`) with the same modal pattern as Android.
- Settings: host, last-port, haptics on/off, natural-scroll, Express Keys edge, active profile.
- Auto-reconnect on `sceneDidBecomeActive`; teardown on `willResignActive`.
- `Info.plist`: `NSLocalNetworkUsageDescription` + `NSBonjourServices = ["_inkbridge._udp"]`
  to reliably trigger the iOS 14+ Local Network permission prompt for raw-socket usage.
- Edge-swipe suppression: `.persistentSystemOverlays(.hidden)`, `.defersSystemGestures(.all)`,
  `.statusBarHidden(true)` on the canvas scene.
- Haptics: `UIImpactFeedbackGenerator` (`.medium` for Express Keys, `.light` for taps).
- `InkBridgeIOSTests` XCTest target running via `xcodebuild test` against a simulator.
- Append iOS test runner config to `openspec/config.yaml`.

### Out of Scope
- Stylus capture (no Apple Pencil on iPhone — no `STYLUS_MOVE`, no `STYLUS_PROXIMITY`).
- USB transport (no `adb reverse` equivalent in the iOS sandbox without MFi/USB accessory).
- iPad layout (deferred to a future change; iPhone-only in this iteration).
- App Store distribution (sideload-only with free Apple ID; 7-day cert cycle).
- Background mode / persistent connection while backgrounded (free-tier sideload cannot
  request the `voip` / `audio` background modes, and arbitrary UDP is not permitted).
- mDNS/Bonjour discovery for the data path (`NSBonjourServices` is included only as a
  permission-prompt trigger; the actual discovery uses the existing custom UDP probe).
- Pressure-curves UI (no pressure data on iPhone).
- Latency histogram / diagnostic overlay (nice-to-have, deferred).
- Shared SPM package for the codec across `macos/` and `ios/` (copy is intentional —
  iOS client is encode-only and the protocol is stable).
- Any change to `macos/`, `android/`, `protocol/README.md`, or `protocol/test-vectors/`.

## Approach (high level)

- **Single Xcode project at `ios/InkBridgeIOS.xcodeproj`** with two targets: app
  (`InkBridgeIOS`) and unit test (`InkBridgeIOSTests`). All sources in the app target — no
  internal SPM package. Sideload signing managed by Xcode's "personal team" automatic
  provisioning.
- **Transport split**: `NWConnection` (UDP, unicast) for the event data path to the resolved
  Mac IP:port; raw BSD socket (`Darwin.socket` + `setsockopt(SO_BROADCAST, 1)` + `sendto`)
  for the discovery probe to `255.255.255.255:4546` and subnet-directed broadcasts. Reply
  is unicast back to the ephemeral source port — same socket reads it via `recvfrom`.
  Mirrors Android's two-channel approach.
- **Codec strategy**: copy `BinaryStylusCodec.swift` from
  `macos/Sources/InkBridgeCore/Protocol/` into `ios/InkBridgeIOS/Protocol/`. Strip the
  decode path (iPhone never receives binary frames). Test vectors (`.hex`) copied into
  the iOS test bundle as resources to guarantee parity with the macOS encode tests.
- **Canvas input**: `UIViewRepresentable` wrapping a `UIView` subclass that overrides
  `touchesBegan/Moved/Ended/Cancelled`. Raw `UITouch` set per event (pointer ID via
  `ObjectIdentifier(touch)`, location, `touch.timestamp`). Routing happens in a pure
  `TouchRouter` struct — fully unit-testable, no UIKit dependencies — driven by injected
  events and clock.
- **Clean-architecture layering**: `Domain` (pure structs, no Foundation beyond `Codable`)
  / `Data` (settings persistence) / `Transport` (UDP send + broadcast discovery) /
  `Protocol` (codec + key codes) / `Input` (touch routing state machine) / `UI` (SwiftUI
  screens). Tests target every layer except `UI` (manual on-device verification for SwiftUI).
- **Landscape lock**: `UIApplicationDelegateAdaptor` returning `.landscape` from
  `supportedInterfaceOrientationsFor:` — there is no SwiftUI-native API on iOS 17.
- **Lifecycle**: SwiftUI `@Environment(\.scenePhase)` triggers connection teardown on
  `.background` and auto-reconnect on `.active`. The Mac server is stateless, so reconnect
  is just reopening `NWConnection` to the same host:port.
- **Strict TDD throughout**: every `TouchRouter`, `BroadcastDiscovery`, `UDPClient`,
  `BinaryStylusCodec.encode`, and `SettingsRepository` function authored RED → GREEN →
  REFACTOR. The test target is created in the first apply batch before any production code.

## Wire protocol coverage

| Event Type            | Code  | iPhone Behavior                                          | Status |
|-----------------------|-------|----------------------------------------------------------|--------|
| `STYLUS_MOVE`         | 0x01  | Not emitted — no stylus on iPhone                        | NOT EMITTED |
| `STYLUS_PROXIMITY`    | 0x02  | Not emitted — no stylus on iPhone                        | NOT EMITTED |
| `STYLUS_BUTTON`       | 0x03  | 1f tap (left), 2f tap (right) — finger taps reuse this   | USED |
| `STYLUS_SCROLL`       | 0x04  | 2-finger drag (translation-dominant)                     | USED |
| `STYLUS_ZOOM`         | 0x05  | 2-finger drag (spread-dominant) with hysteresis          | USED |
| `CURSOR_DELTA`        | 0x06  | 1-finger drag, plus held drag in double-tap-drag window  | USED |
| `KEY_EVENT`           | 0x07  | Express Keys sidebar shortcut + modifiers                | USED |
| `CAPTURE_REQUEST`     | 0x08  | "Capture from Mac" modal sends this and reads response   | USED |

**Server-side changes required: zero.** The protocol is event-pushed; the server already
ignores omitted event types because they simply never arrive.

## Project layout

```
ios/
├── InkBridgeIOS.xcodeproj
├── InkBridgeIOS/
│   ├── App/                  # SwiftUI App entry, Scene, Info.plist, AppDelegate (landscape lock)
│   ├── Domain/               # StylusEvent, ExpressKey, ExpressKeyProfile, ConnectionState, DiscoveredHost
│   ├── Data/                 # SettingsRepository (UserDefaults + Codable JSON for profiles)
│   ├── Transport/            # UDPClient (NWConnection unicast), BroadcastDiscovery (BSD socket)
│   ├── Protocol/             # BinaryStylusCodec.swift (encode-only copy from macos/), MacKeyCodes.swift
│   ├── Input/                # TouchRouter (1f drag → cursor delta, 2f scroll/pinch, double-tap-drag SM)
│   └── UI/Screens/           # ConnectionScreen, CaptureScreen, ExpressKeysSettings, CaptureFromMacModal
└── InkBridgeIOSTests/
    ├── Vectors/              # copies of protocol/test-vectors/*.hex
    ├── ProtocolTests/        # BinaryStylusCodec round-trip vs. shared vectors
    ├── TransportTests/       # mocked UDP sender, mocked broadcast socket
    ├── InputTests/           # TouchRouter state machine, double-tap-drag window edge cases
    └── DataTests/            # SettingsRepository persist/load profiles
```

## Risks

| Risk                                                              | Likelihood | Mitigation |
|-------------------------------------------------------------------|------------|------------|
| Local Network permission re-prompt every 7 days on sideload       | High       | Settings banner explains; UI handles "no servers found" gracefully with manual-IP fallback. Not fixable without paid Developer account. |
| Wi-Fi router blocks broadcast (guest/enterprise networks)         | Medium     | Manual-IP entry stays prominent; empty-state CTA. No USB fallback on iOS — accept this constraint. |
| BSD socket discovery code is lower-level and platform-fragile     | Medium     | Cover with unit tests using a mock socket layer; integration test gated `// requires device`. |
| Double-tap-drag 350 ms window precision on slow devices           | Low        | Use raw `UITouch.timestamp` (avoids `UITapGestureRecognizer` system delay); parameterize the window constant for testability. |
| Simulator cannot reach broadcast destinations reliably            | Medium     | Mock socket layer for unit tests; mark broadcast integration tests as device-only. |
| Codec drift if `protocol/README.md` adds new event types          | Low        | Both copies (macOS + iOS) must pass the same `.hex` test vectors; vectors copied into iOS test bundle. |
| `xcodebuild test` simulator boot is slow (60–120 s first run)     | Low        | Use `build-for-testing` + `test-without-building` split for fast iteration after first build. |
| `NWConnection` rejects broadcast destinations silently            | Resolved   | Explore phase confirmed — discovery uses raw BSD sockets, NOT `NWConnection`. |

## Rollback

The change is fully additive — a new directory under `ios/` and one config append. To revert:
1. Delete the `ios/` directory.
2. Revert the iOS testing config block in `openspec/config.yaml`.
3. No `macos/`, `android/`, or `protocol/` files are touched, so nothing else needs reverting.

The Mac server keeps responding to broadcast probes from any client — the Android client
is unaffected by removing or keeping the iOS target.

## Rollout

Sideload-only, no CI for iOS in this iteration, no release versioning:
1. Open `ios/InkBridgeIOS.xcodeproj` in Xcode.
2. Set Signing & Capabilities → Team to a personal Apple ID team.
3. Connect an iPhone, enable Developer Mode (Settings → Privacy & Security).
4. Build & run; on first launch, grant Local Network permission when prompted.
5. App auto-discovers the running Mac server on the same Wi-Fi within ~2 s; tap to connect.
6. Re-sign every 7 days as the personal certificate expires (known free-account constraint).

## Dependencies

- Xcode 15+ (ships iOS 17 SDK and the iPhone 16 simulator used by the test runner).
- A personal Apple ID for sideload signing (any free account).
- The macOS server must be running on the same Wi-Fi LAN as the iPhone for discovery.
- The router must allow UDP broadcast on the LAN (most home routers do; some guest /
  enterprise networks block it — manual-IP fallback covers that case).

## Success criteria

- [ ] iPhone discovers a running Mac server on the same Wi-Fi within 2 s of opening
      the connection screen, without typing an IP.
- [ ] 1-finger drag on the canvas moves the macOS cursor with end-to-end RTT under 50 ms
      on local Wi-Fi (verified with on-screen finger position vs. mouse target).
- [ ] 2-finger drag scrolls or zooms the active app correctly with hysteresis (no flicker
      between scroll and zoom mid-gesture).
- [ ] Double-tap-drag inside the 350 ms window initiates a drag-select in Finder.
- [ ] Tapping an Express Key injects the mapped shortcut (e.g., `⌘C`) on the Mac.
- [ ] "Capture from Mac" modal records a key combo on the Mac and assigns it to a slot.
- [ ] Express Key profiles and settings (host, port, haptics, natural-scroll, edge,
      active profile) persist across app restart and across sideload re-signing
      (UserDefaults survives reinstall when the bundle ID matches).
- [ ] Backgrounding the app tears the connection down; foregrounding auto-reconnects
      to the last host:port within 1 s (Mac server is stateless — no handshake).
- [ ] `xcodebuild test -scheme InkBridgeIOS -destination 'platform=iOS Simulator,name=iPhone 16'`
      passes on a clean checkout.
- [ ] Zero changes to `macos/`, `android/`, `protocol/README.md`, or `protocol/test-vectors/`.

## Open questions

None at this stage. The 13 iOS-specific questions raised in exploration are all resolved
(see `explore.md` and engram observation `sdd/ios-client/explore`). Remaining decisions —
exact simulator name, exact `Info.plist` permission strings, exact pinch/scroll
hysteresis ratio — are spec-level details, not proposal-level scope choices.
