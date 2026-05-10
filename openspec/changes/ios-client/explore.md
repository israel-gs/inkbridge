# Exploration: ios-client

**Change**: ios-client
**Date**: 2026-05-09
**Artifact store**: hybrid (openspec + engram)
**Strict TDD**: ACTIVE — `xcodebuild test` is the iOS test runner

---

## Current State

InkBridge has two clients today:
- **Android** (Kotlin + Jetpack Compose): full stylus capture, two-finger gestures, Express Keys, Wi-Fi + USB transport, custom UDP broadcast discovery on `:4546`.
- **macOS** (Swift Package, SwiftUI): server-only, zero UI on the canvas, status window with toggles.

The server protocol is fully documented in `protocol/README.md`. The Swift codec (`macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift`) is a zero-dependency, little-endian binary encoder/decoder covering all event types. The Mac's `BroadcastResponder.swift` uses raw BSD sockets to listen on `:4546`, match `INKB?` probes, and reply unicast with `INKB!<version>|<dataPort>|<hostname>`.

The Android discovery client (`BroadcastDiscoveryRepository.kt`) sends probes to both `255.255.255.255` and all directed broadcast addresses every 2 seconds, with a 1-second `soTimeout` receive window and a 10-second stale-prune threshold.

There is no iOS client. The new target is **iPhone-only**, positioned as a wireless trackpad + Express Keys remote — NOT a drawing tablet (no stylus, no `STYLUS_MOVE`, no `STYLUS_PROXIMITY`).

---

## Affected Areas

- `protocol/README.md` — read-only reference; no changes.
- `macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift` — candidate for sharing or copying.
- `macos/Package.swift` — relevant if we extract a shared Swift package (Option A for codec sharing).
- `openspec/config.yaml` — needs iOS testing config appended.
- `ios/` — new top-level directory (does not exist yet).

---

## Investigation: iOS-Specific Questions

### a. Networking: `Network.framework` (`NWConnection`) vs. BSD sockets for data path

**`NWConnection` with `NWParameters.udp`** is the correct choice for the data (event) path. It is the Apple-sanctioned high-level API, integrates with the system's VPN/routing stack, and works with the Local Network permission subsystem on iOS 14+. The macOS server already uses `NWListener` (via `UDPListener.swift`) for receiving — symmetric `NWConnection` on the iOS sender preserves consistency.

Raw BSD sockets work on iOS for unicast UDP send-only flows (no entitlement needed for basic unicast). The discovery path already confirms this because Android uses `DatagramSocket` which maps to POSIX sockets internally.

**Key difference for iOS**: `NWConnection` abstracts the socket lifecycle and automatically triggers the Local Network permission prompt on first use (see section c). BSD sockets bypass this in surprising ways — the permission dialog may not appear until a real packet is sent, and behavior varies by iOS version. Using `NWConnection` is safer because Apple's stack handles the prompt lifecycle deterministically.

**Recommendation**: `NWConnection` for the data path (event sender); raw BSD sockets (via Darwin's `socket()` / `setsockopt()`) for the discovery send path only if `NWConnection` broadcast has issues (see section b).

### b. Discovery: UDP broadcast on `:4546`, `SO_BROADCAST`, and `NSBonjourServices`

**`NWConnection` cannot set `SO_BROADCAST`**. The `NWParameters.udp` API does not expose `setsockopt(SO_BROADCAST)`. To send to a broadcast address from `NWConnection`, you would create the connection with `NWEndpoint.hostPort(host: "255.255.255.255", port: 4546)` — but Apple's Network.framework rejects broadcast-destination connections on iOS with an immediate `failed` state (the sandbox blocks it silently).

**Workaround**: The discovery sender on iOS MUST use raw BSD sockets (`socket()` + `setsockopt(SO_BROADCAST, 1)` + `sendto()`), exactly mirroring what `BroadcastResponder.swift` does on the Mac server side. This is the same pattern the Android `BroadcastDiscoveryRepository.kt` uses with Java `DatagramSocket(broadcast = true)`. There is no special entitlement needed for `SO_BROADCAST` from within the iOS app sandbox — it is allowed.

**Directed broadcast vs. limited broadcast**: The iOS client should send to both `255.255.255.255:4546` and the subnet directed broadcast (derived from the device's IP + netmask). Some home routers drop `255.255.255.255`; sending both maximizes reliability, exactly as Android does.

**Receiving the unicast reply**: The reply from the Mac server is unicast back to the iPhone's ephemeral source port. If we use a raw BSD socket for sending (bound to an ephemeral port via `bind(0)`), the reply arrives on that same socket — no additional listener needed.

**`NSBonjourServices` in Info.plist**: The Local Network permission prompt on iOS 14+ fires reliably when the app first performs any LAN operation — multicast, broadcast, or unicast to a non-internet address — through `Network.framework`. However, when using raw BSD sockets (`socket()` / `sendto()`), iOS may NOT trigger the prompt automatically on all versions. The safest approach is:
1. Include `NSLocalNetworkUsageDescription` (mandatory string).
2. Include `NSBonjourServices` with `_inkbridge._udp` even though we are NOT using Bonjour — this key is what tells the OS to show the permission dialog for local network access, and Apple's entitlement checker uses its presence as a signal. Without it, the prompt may silently suppress on some iOS versions when using raw sockets.

This was partially anticipated in the kickoff note (#218): "NSBonjourServices (`_inkbridge._udp`) so the prompt fires cleanly on first send."

**Discovery flow on iPhone**:
1. App opens → attempt first probe send (raw BSD socket to broadcast) → OS shows Local Network permission prompt.
2. User grants → subsequent probes go out; server replies unicast.
3. App parses `INKB!<version>|<dataPort>|<hostname>` reply, extracts source IP from `recvfrom` `sockaddr_in`.
4. Discovered host appears in the connection list. Probe interval: 2 s; stale threshold: 10 s (matching Android).

### c. Local Network Permission (iOS 14+)

`NSLocalNetworkUsageDescription` must be present in `Info.plist` with a user-visible string explaining why LAN access is needed (e.g., "InkBridge needs Local Network access to discover your Mac and send input events."). Without this key, the first LAN packet silently fails.

The permission is **one-time per app install** — the user is prompted once, and the decision persists (resettable in Settings → Privacy). If the user denies it, all LAN traffic (including unicast to a typed IP) is silently dropped. The iOS app must handle this gracefully: detect no response after N probes and show a banner explaining how to grant permission in Settings.

Permission is NOT revoked by app updates; it IS revoked by uninstall. For a sideload app (7-day cert), the app is reinstalled every 7 days when re-signing — so the permission prompt appears on every cert cycle. This is a known sideload UX friction, not fixable without a paid Developer account.

### d. Touch Input: SwiftUI gestures vs. UIKit `UITouch` for the canvas

**SwiftUI gestures alone are insufficient** for the canvas requirements. SwiftUI's `MagnificationGesture`, `DragGesture(minimumDistance: 0)`, and `TapGesture` are high-level recognizers that:
- Do not give simultaneous raw multi-finger positions (pointer IDs, per-touch XY at each moment).
- Cannot implement the double-tap-drag (350 ms window) precisely — SwiftUI's tap recognizers add a system delay.
- Cannot distinguish a 2-finger simultaneous gesture starting from a 1-finger tracking state without racing recognizer states.

**Recommendation**: Use a `UIView` subclass that overrides `touchesBegan/Moved/Ended/Cancelled` for the canvas, hosted in SwiftUI via `UIViewRepresentable`. This mirrors the Android approach (which uses `pointerInteropFilter` to intercept raw `MotionEvent`s — see `CaptureSurface.kt` lines 154–278).

The `UIView` canvas approach gives:
- Full `UITouch` set on every event: ID (pointer identity via `ObjectIdentifier(touch)`), phase, location, `majorRadius`, `force` (irrelevant on iPhone — always 0 since no 3D Touch on modern iPhones).
- Simultaneous multi-touch without SwiftUI recognizer arbitration.
- Precise timestamp (`touch.timestamp`) for the 350 ms double-tap-drag window.

**SwiftUI for everything else** (navigation, settings, connection screen, Express Keys bar overlay): SwiftUI is appropriate and preferred.

**Gesture routing logic** (mirrors Android `CaptureSurface.kt` routing):
- 1 finger → trackpad cursor delta (`CURSOR_DELTA 0x06`). Single tap → `STYLUS_BUTTON 0x03` (click).
- 2 fingers moving → scroll (`STYLUS_SCROLL 0x04`) or pinch (`STYLUS_ZOOM 0x05`) by comparing spread vs. translation delta.
- 2-finger tap → right-click.
- Double-tap-drag (350 ms window): first tap UP, then within 350 ms a DOWN again followed by MOVE → drag-select.
- 3+ fingers: ignore.

**Pinch vs. scroll disambiguation**: track the ratio of spread-change to translation-change per frame. If |spread_delta| / |translation_delta| > 1.5 → zoom; otherwise → scroll. Hysteresis prevents mode flip mid-gesture.

### e. App Lifecycle / Background Behavior

iOS suspends apps within seconds of backgrounding (typically 5–10 s for foreground apps losing focus). UDP sockets created via `NWConnection` are automatically cancelled on suspension. Raw BSD sockets are closed by the OS when the process is suspended.

**What happens mid-session**: the data socket is silently torn down. When the user returns to the foreground, the app must re-establish the `NWConnection` to the previously connected host:port. The Mac server is stateless (no handshake, no session ID) — the iPhone can simply start sending events again after reopening the connection.

**Background Modes capability** is NOT available for personal sideloads with a free Apple ID. Even if it were, "Network" background mode is for VoIP/audio, not arbitrary UDP. This is a hard constraint: the app MUST reconnect on foreground. Auto-reconnect (matching Android's `KEY_AUTO_RECONNECT` pattern) should be the default behavior.

**Scene lifecycle hook**: implement `sceneDidBecomeActive` / `sceneWillResignActive` (or SwiftUI `.onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification))`) to trigger disconnect on resign and auto-reconnect on reactivate.

### f. Landscape Lock

`Info.plist` key `UISupportedInterfaceOrientations` (for iPhone) must list ONLY:
- `UIInterfaceOrientationLandscapeLeft`
- `UIInterfaceOrientationLandscapeRight`

Omit `UIInterfaceOrientationPortrait` and `UIInterfaceOrientationPortraitUpsideDown`.

For SwiftUI + UIWindowScene projects, also set the `UIWindowSceneSessionRoleApplication` → `UISceneConfigurationName` scene manifest in Info.plist, OR use `AppDelegate`'s `supportedInterfaceOrientationsFor:` returning `.landscape`.

In a pure SwiftUI app (no AppDelegate), override via `UIApplicationDelegateAdaptor` + a custom `AppDelegate` implementing `supportedInterfaceOrientationsFor:` returning `.landscape`. This is the only reliable way on iOS 16+ — SwiftUI has no native landscape-lock API.

### g. Edge-Swipe Suppression

Two types of system gesture interference in landscape:
1. **Bottom edge swipe** → home bar / app switcher.
2. **Top edge swipe** → Control Center (landscape: right edge on iPhone).

**SwiftUI modifiers needed** (iOS 16+):
- `.persistentSystemOverlays(.hidden)` — hides the home indicator bar, reducing its grab area.
- `.defersSystemGestures(on: .all)` — tells the system the app wants to handle the first swipe attempt itself; if the app doesn't consume it, the system gesture fires on a second swipe. This is the best available mechanism for the canvas view.
- `.statusBarHidden(true)` — removes the status bar, eliminating its swipe target.

Note: `.defersSystemGestures` requires iOS 16+. With iOS 17 as the minimum, this is clean. There is no `UIScreenEdgePanGestureRecognizer` equivalent in SwiftUI — must be applied on the root View of the canvas scene or a `UIViewController` presenting it.

**Remaining friction**: the home bar swipe on iPhone cannot be fully suppressed (App Store guideline), but `.persistentSystemOverlays(.hidden)` makes it require a deliberate double-swipe from the very bottom edge, which is acceptable for a personal tool.

### h. Haptics

`UIImpactFeedbackGenerator(style: .medium)` for Express Key taps. `.light` for cursor click confirmation (single tap). This matches Android's `VibrationEffect` haptic feedback in `SettingsRepository` (key `KEY_HAPTIC_INTENSITY`).

On iOS, haptic intensity is not directly configurable by the app (unlike Android). The style (light/medium/heavy/rigid/soft) is the only control. For a personal tool, `.medium` for Express Keys and `.light` for trackpad taps are appropriate defaults.

Expose a Settings toggle "Enable haptics" backed by `@AppStorage("pref_haptics_enabled")` (Boolean, default true). This mirrors Android's haptic intensity preference pattern but simplified.

### i. Express Keys + Profiles Persistence

Android uses `SettingsRepository` (SharedPreferences + JSON string for profiles) backed by `ExpressKeyProfileJson`.

**iOS recommendation**: `JSONEncoder/Decoder` to `UserDefaults` for the full profile list, matching Android's pattern, but using native Swift `Codable`. Concretely:

- Primitives (host, port, haptics enabled, natural scroll, express keys edge, active profile ID): `@AppStorage(key)` directly — this is `UserDefaults`-backed and works correctly with SwiftUI.
- Profile list (array of `ExpressKeyProfile` with nested `ExpressKey` array): `JSONEncoder().encode(profiles)` → `Data` → stored with `UserDefaults.standard.set(data, forKey: "pref_express_key_profiles")`. On read: `UserDefaults.standard.data(forKey:)` → `JSONDecoder().decode([ExpressKeyProfile].self, from:)`.

This avoids the `Codable` to file-in-Documents approach (unnecessary complexity for a personal spike) and avoids a Core Data dependency.

The iOS domain model `ExpressKeyProfile` and `ExpressKey` should be **newly defined Swift structs** conforming to `Codable`. Do NOT share JSON format byte-for-byte with Android (both sides are independent clients; they never exchange profile data). The profile struct should match the Android shape for conceptual parity.

### j. Codec Sharing: Shared Swift Package vs. Copy

**Option A — Shared Swift Package** (`protocol/` or `shared/` as a local SPM package consumed by both `macos/` and `ios/`):
- Pros: single source of truth for `BinaryStylusCodec`, `StylusEvent`, `KeyAction`, `PacketHeader`, `ProtocolError`. Any bug fix applies to both. Test vectors tested once.
- Cons: requires creating a new SPM package (new `Package.swift` at `shared/swift/`), updating `macos/Package.swift` to reference it as a local dependency, and wiring it into the Xcode project for iOS. Adds a build-graph dependency that complicates both `swift test` (mac) and `xcodebuild test` (iOS). For a personal spike with two engineers (zero), this is overengineering.

**Option B — Copy** (`ios/Sources/InkBridgeIOSCore/Protocol/BinaryStylusCodec.swift`):
- Pros: zero build-graph changes, immediate. The file is 440 lines and self-contained (no imports beyond Foundation). Copy the `Data` private extensions too.
- Cons: drift risk if the protocol ever adds an event type. Mitigation: the protocol's `README.md` and test vectors remain the single source of truth; both copies must pass the same `.hex` vectors.
- Effort: Low.

**Recommendation: Option B (copy)**, with a deliberate documentation comment at the top of the iOS copy: `// Copied from macos/Sources/InkBridgeCore/Protocol/BinaryStylusCodec.swift — keep in sync with protocol/README.md.` The user values minimalism (personal spike, no team). A shared package adds CI complexity (two `swift test` roots, a local-package `path:` reference) that pays off only if the protocol is actively evolving. Given that the iOS client emits only a subset of event types, the copy is also an opportunity to remove dead branches (`STYLUS_MOVE`, `STYLUS_PROXIMITY`, `captureResponse` decode) from the iOS copy's decoder — this is actually safer, since the iOS target never needs to decode anything (it is send-only).

Note: the codec decode path is NOT needed on iOS at all — the iPhone client is a pure sender. Only the encode path is needed. This further reduces the value of sharing a full bidirectional codec.

### k. Project Layout

```
ios/
├── InkBridgeIOS.xcodeproj/       (or .xcworkspace if CocoaPods/SPM integration needed)
│   └── project.pbxproj
├── InkBridgeIOS/                  # App target sources
│   ├── App/
│   │   ├── InkBridgeIOSApp.swift  # @main, AppDelegate adaptor for landscape lock
│   │   └── Info.plist
│   ├── Domain/
│   │   ├── StylusEvent.swift      # iOS subset — no .move, .proximity
│   │   ├── ExpressKeyProfile.swift
│   │   ├── ConnectionState.swift
│   │   └── DiscoveredHost.swift
│   ├── Data/
│   │   ├── SettingsRepository.swift  # UserDefaults + JSONEncoder/Decoder
│   │   └── DiscoveryRepository.swift # BSD socket broadcast probe
│   ├── Transport/
│   │   └── UDPSender.swift           # NWConnection unicast event sender
│   └── UI/
│       ├── Connection/
│       │   ├── ConnectionView.swift
│       │   └── ConnectionViewModel.swift
│       ├── Canvas/
│       │   ├── CanvasView.swift       # UIViewRepresentable wrapping CanvasUIView
│       │   ├── CanvasUIView.swift     # UIView with touchesBegan/Moved/Ended
│       │   ├── CanvasViewModel.swift
│       │   └── GestureProcessor.swift # Routing + gesture state machine
│       ├── ExpressKeys/
│       │   ├── ExpressKeyBar.swift
│       │   └── ExpressKeySettingsView.swift
│       └── Settings/
│           └── SettingsView.swift
├── InkBridgeIOSTests/             # XCTest unit test target
│   ├── Protocol/
│   │   └── BinaryStylusCodecTests.swift
│   ├── Discovery/
│   │   └── DiscoveryRepositoryTests.swift
│   └── Gestures/
│       └── GestureProcessorTests.swift
└── Makefile                        # `make test` → xcodebuild test
```

**Xcode project vs. SPM-only**: The app target requires an Xcode project (`.xcodeproj`) because:
1. iOS apps need an explicit code-signing identity (even for sideload via free Apple ID, Xcode manages provisioning).
2. Info.plist and entitlements are Xcode project concepts.
3. `xcodebuild test` requires a scheme defined in `.xcodeproj`.

SPM-only (no `.xcodeproj`) works for pure libraries but not for iOS app targets with signing. The test library portions (`InkBridgeIOSCore`) can be an SPM package imported by the Xcode project, but the project file itself is mandatory.

### l. Test Runner for Strict TDD

```bash
xcodebuild test \
  -project ios/InkBridgeIOS.xcodeproj \
  -scheme InkBridgeIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -resultBundlePath /tmp/inkbridge-ios-test.xcresult
```

Add a `Makefile` target:
```makefile
test-ios:
	xcodebuild test \
	  -project ios/InkBridgeIOS.xcodeproj \
	  -scheme InkBridgeIOS \
	  -destination 'platform=iOS Simulator,name=iPhone 16' \
	  -resultBundlePath /tmp/inkbridge-ios-test.xcresult 2>&1 | xcpretty || true
```

The simulator name should match whatever is installed locally. `iPhone 16` is safe for iOS 17+ simulator bundles that ship with Xcode 15+. The exact simulator name can be parameterized: `SIMULATOR ?= iPhone 16`.

**Strict TDD discipline for apply/tasks phases**: EVERY new function in `GestureProcessor`, `DiscoveryRepository`, `UDPSender`, and `BinaryStylusCodecTests` MUST have a failing test written first (RED), then the implementation (GREEN), then refactor. The test target `InkBridgeIOSTests` must be created as part of the first apply batch before any production code is added.

### m. Feature Parity Table

| Android Feature | iPhone Behavior | Status |
|---|---|---|
| Stylus stroke (pressure, tilt) | No stylus on iPhone — not applicable | ❌ skip |
| Stylus hover | No stylus — not applicable | ❌ skip |
| Barrel button (S Pen side) | Not applicable | ❌ skip |
| 1-finger drag → cursor delta | 1-finger drag → `CURSOR_DELTA (0x06)` | ✅ port |
| 1-finger tap → left click | 1-finger tap → `STYLUS_BUTTON (0x03)` flags=0x00 (no button bits) | ✅ adapt |
| Double-tap drag (350 ms window) → drag-select | Same gesture → `CURSOR_DELTA` held | ✅ port |
| 2-finger scroll → `STYLUS_SCROLL (0x04)` | Same | ✅ port |
| 2-finger pinch → `STYLUS_ZOOM (0x05)` | Same | ✅ port |
| 2-finger tap → right-click | 2-finger tap → `STYLUS_BUTTON (0x03)` flags=BUTTON_PRIMARY (0x08) | ✅ adapt |
| Express Keys sidebar (6 buttons) | Same → `KEY_EVENT (0x07)` + modifier hold | ✅ port |
| Express Key profiles (JSON, UUID) | Same structure, Swift Codable | ✅ adapt |
| Capture from Mac (keystroke capture) | `CAPTURE_REQUEST (0x08)` — same protocol | ✅ port |
| Wi-Fi auto-discovery (broadcast probe `:4546`) | Same probe, BSD socket | ✅ port |
| Manual IP entry | Same | ✅ port |
| USB via `adb reverse` | Not available on iOS — omit tab | ❌ skip |
| Auto-reconnect on foreground | Same behavior, foreground hook | ✅ adapt |
| Natural scroll toggle | Same pref | ✅ port |
| Haptic feedback | `UIImpactFeedbackGenerator`, on/off toggle | ✅ adapt |
| Click flash visual ripple | Same canvas animation | ✅ port |
| Per-app pressure curves | N/A — no pressure data | ❌ skip |
| Latency histogram | Nice-to-have; omit from v1 | ❌ skip |
| Connection screen (portrait + landscape) | Landscape-only; simpler (no USB tab) | ✅ adapt |
| OLED black canvas + dot grid | Same visual design | ✅ port |
| Finger indicator rings per touch | Same (up to 2 fingers) | ✅ port |

**Net**: 14 features ported/adapted, 7 skipped (all stylus-specific or USB-only).

---

## Approaches

### Approach 1 — Xcode project (`.xcodeproj`) with embedded SPM dependency for core logic

Create `ios/InkBridgeIOS.xcodeproj` with two targets: the app target (`InkBridgeIOS`) and a unit test target (`InkBridgeIOSTests`). Core logic (codec, discovery, transport) lives in Swift source files added directly to the app target (no separate SPM package for them). Tests import the app module.

- **Pros**: simplest to bootstrap (Xcode wizard generates the skeleton); sideload signing works out of the box; `xcodebuild test` command is standard; no SPM graph complexity.
- **Cons**: `.xcodeproj` is notoriously merge-unfriendly (pbxproj is not human-readable); all source management is through Xcode's project editor.
- **Effort**: Low (set up) + Low (ongoing, solo project).

### Approach 2 — SPM package for library + Xcode project for app target only

Extract `InkBridgeIOSCore` as a local SPM package at `ios/InkBridgeIOSCore/`. The Xcode project has a single app target that adds `ios/InkBridgeIOSCore` as a local package dependency. Tests live in the SPM package (`swift test`) for the library and in `xcodebuild test` for UI tests.

- **Pros**: clean separation; SPM package is testable without launching a simulator (just `swift test`); enables code sharing path later.
- **Cons**: two test commands (`swift test` + `xcodebuild test`); more setup; local SPM packages referenced from an Xcode project require Xcode 12+ dependency resolution which adds friction for sideload.
- **Effort**: Medium.

### Recommendation: Approach 1

For a personal spike targeting sideload only, Approach 1 (Xcode project, all sources in the app target) is the right choice. The team is one person; merge conflicts in pbxproj are a non-issue. Tests run via `xcodebuild test`. If a shared package is needed in the future, the core logic files can be moved into an SPM package without changing the public surface.

---

## Key Discoveries (iOS API Gotchas)

1. **`NWConnection` cannot send to broadcast addresses on iOS** — the connection transitions to `failed` immediately. Must use raw BSD sockets (`Darwin.socket`) for the discovery probe. No entitlement needed for `SO_BROADCAST`.

2. **`NSBonjourServices` triggers the Local Network permission prompt even for non-Bonjour apps** — Apple's OS prompt machinery reads this key as a signal to show the dialog when LAN access is attempted. Without it, raw socket operations may fail silently on first run. Include `_inkbridge._udp` in `NSBonjourServices` array.

3. **Local Network permission is lost on each sideload reinstall** (every 7 days) — the prompt will appear again every cert cycle. This is not fixable for free-account sideloads. Design the UX to handle repeated first-run permission gracefully.

4. **iPhone has no 3D Touch / Force Touch on current hardware** — `UITouch.force` is always 0 on iPhone 15+. Do not attempt to use touch force as a pressure substitute.

5. **`UIView.touchesBegan/Moved/Ended`** can track up to 5 simultaneous touches on iPhone (hardware limit is device-specific but always ≥ 5). We only care about ≤ 2 for our routing logic.

6. **Landscape lock requires `UIApplicationDelegateAdaptor`** in a pure SwiftUI lifecycle app — there is no SwiftUI-native API for this in iOS 17.

7. **`.defersSystemGestures(on: .all)` requires a first-swipe attempt** — the system gesture still fires on a second swipe. This is the intended behavior (Apple's App Store guidelines require home gesture accessibility). For a personal tool this is acceptable.

8. **The iOS codec copy can drop the decode path entirely** — the iPhone client is send-only (it does NOT receive binary frames from the server). Only `BinaryStylusCodec.encode()` is needed. The decode path should be removed from the iOS copy to reduce surface area and eliminate dead code from the test suite.

---

## Risks

1. **Local Network permission UX on sideload** — prompt fires on each 7-day reinstall. No workaround. Document in a `README` or settings banner.
2. **Broadcast blocking on the Wi-Fi router** — some enterprise/guest networks block broadcast. The iPhone has no USB fallback (unlike Android). Must display a "No servers found — enter IP manually" fallback prominently.
3. **Discovery via BSD sockets** — raw socket code is lower-level and more prone to platform-specific bugs than `Network.framework`. Must be covered by integration tests (requires an actual LAN or a loopback test harness).
4. **Double-tap-drag 350 ms window precision** — iOS gesture recognizer `UITapGestureRecognizer` adds system delay; using raw `UITouch` timestamps avoids this, but the timing window is tight on slow devices. Parameterize the window constant for testability.
5. **Simulator limitations for UDP testing** — iOS Simulator can send/receive UDP on the Mac loopback, but broadcast to `255.255.255.255` may not reach the Mac server process. Discovery tests will need a mock socket layer for unit tests; integration tests should be flagged with `// requires device`.
6. **Codec drift** — if `protocol/README.md` adds new event types, both the macOS and iOS copies of `BinaryStylusCodec.swift` must be updated manually. The protocol test vectors (`.hex` files) must be copied into the iOS test bundle as a `Resources` target, mirroring `macos/Tests/InkBridgeCoreTests/Vectors/`.
7. **Strict TDD with Xcode simulators is slower than `swift test`** — plan for `xcodebuild test` runs taking 60–120 s due to simulator boot. Use the `build-for-testing` + `test-without-building` split for faster iteration after the first build.

---

## Affected Files (new, no existing files modified)

- `ios/` — entire new directory (Xcode project + sources + tests)
- `openspec/changes/ios-client/` — SDD artifacts
- `openspec/config.yaml` — append iOS testing config (minor addition, not a breaking change)

No changes to:
- `macos/` — zero server-side changes required
- `android/` — no changes
- `protocol/README.md` — no protocol changes
- `protocol/test-vectors/` — vectors copied into iOS test bundle, not modified

---

## Ready for Proposal

**Yes.** All key iOS API questions are resolved. The exploration surfaces one significant constraint (NWConnection broadcast limitation → BSD sockets for discovery), confirms the codec copy recommendation, and validates the touch input approach (UIViewRepresentable). The proposal phase can proceed with these answers as grounding.
