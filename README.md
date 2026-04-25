# InkBridge

Wireless drawing tablet for macOS, powered by your Android device's stylus.

InkBridge captures raw S Pen events on Android (position, pressure, tilt, barrel buttons, two-finger gestures) and streams them over Wi-Fi or USB to a macOS server that injects them as native tablet, scroll, and click events. Pressure-sensitive apps — Krita, Photoshop, Affinity, Procreate-on-Sidecar — receive real brush modulation. No driver, no kernel extension, no MDM profile.

This is a personal spike, not a product. There is no notarized installer, no auto-update, no telemetry. If something breaks, read the code.

---

## What it does

| Capability | Source on Android | Effect on Mac |
|------------|-------------------|---------------|
| Stylus stroke | S Pen tip + pressure + tilt | Native tablet event with pressure modulation in any drawing app |
| Hover | S Pen tip near screen | Cursor moves; no click |
| Barrel button | S Pen side button | Right-click |
| 1-finger drag | One finger on canvas | Cursor delta (trackpad-style) |
| 1-finger tap | Tap and lift | Left-click at cursor |
| 2-finger scroll | Two-finger drag | `kCGEventScrollWheel` with phase + momentum |
| 2-finger pinch | Two-finger zoom | `Cmd+scroll` (works in Krita, Preview, Affinity, browsers) |
| 2-finger tap | Two-finger tap | Right-click |

The Mac side renders nothing visual. It is a server: receive packets, post events, update stats.

---

## How it looks

### Android — connect (Wi-Fi)

The first screen picks the transport. Wi-Fi mode asks for the Mac's LAN IP. Port defaults to `4545`.

![Android connection screen — Wi-Fi tab](docs/images/android-connect-wifi.png)

### Android — connect (USB via `adb reverse`)

USB mode pins the host to `127.0.0.1` and shows the exact `adb reverse` command, with a copy button. This is the lowest-latency path because traffic stays on-device through the USB tunnel.

![Android connection screen — USB tab](docs/images/android-connect-usb.png)

### Android — capture surface

Once connected the canvas takes over: dot grid, OLED black, edge-to-edge. The pill in the top-left shows the live transport (green dot = active). The cyan glow is the optional click-flash visual feedback for tap and right-click confirmations. Top-right controls: fullscreen toggle, settings (natural scrolling, auto-reconnect, haptic intensity, click flash), disconnect.

![Android capture surface — connected, click flash visible](docs/images/android-canvas-connected.png)

### macOS — server window

The Mac app is intentionally tiny: a state pill, the USB tunnel chip (which auto-runs `adb reverse` when a device is plugged in), three live counters, and a Start/Stop toggle. When idle the button reads "Start Server" and rebinds the listeners; when listening it reads "Stop Server".

![macOS server window — listening on port 4545](docs/images/macos-server-listening.png)

---

## Repository layout

```
inkbridge/
├── android/                      # Kotlin + Jetpack Compose client
│   └── app/src/main/kotlin/com/inkbridge/
│       ├── data/                 # SettingsRepository, transport sockets
│       ├── domain/               # StylusEvent, GestureEvent, ConnectionState
│       └── ui/screens/           # Compose UI (connection, capture, settings)
├── macos/                        # Swift Package (executable + library)
│   ├── Package.swift
│   ├── InkBridge.entitlements    # Accessibility + tablet event entitlements
│   ├── Sources/InkBridge/        # SwiftUI app shell (ContentView, ServerViewModel, StatusView)
│   └── Sources/InkBridgeCore/    # Domain
│       ├── Transport/            # UDPListener, TCPListener (Network framework)
│       ├── Injection/            # CGEventInjector — tablet, scroll, zoom, momentum
│       ├── Server/               # InkBridgeServer — wires transport → injection
│       └── Codec/                # BinaryStylusCodec — wire format encode/decode
├── protocol/                     # Wire-format spec + canonical test vectors (.hex)
│   ├── README.md                 # Frame layout, byte order, flags, payloads
│   └── test-vectors/             # Round-trip vectors used by both platforms' tests
├── openspec/                     # SDD artifacts (proposals, specs, design, tasks)
└── docs/images/                  # README screenshots
```

The protocol directory is the source of truth. Both client and server load the same `.hex` test vectors during test runs.

---

## Wire protocol (v1)

- 16-byte fixed header + variable payload, **little-endian**, no handshake.
- Same frame format on UDP (Wi-Fi) and TCP (USB loopback).
- Sequence number is per-session and wraps at 2³². Out-of-order datagrams on UDP are dropped server-side.
- Receiver discards any unknown `event_type` rather than crashing.

| Event | Code | Total size | Use |
|-------|------|-----------|-----|
| `STYLUS_MOVE` | `0x01` | 36 B | Position + pressure + tilt |
| `STYLUS_PROXIMITY` | `0x02` | 20 B | Stylus enters/leaves hover range |
| `STYLUS_BUTTON` | `0x03` | 20 B | Barrel buttons, finger taps |
| `STYLUS_SCROLL` | `0x04` | 20 B | Two-finger scroll deltas (extended) |
| `STYLUS_ZOOM` | `0x05` | 20 B | Two-finger pinch (extended, `Cmd+scroll` fallback) |
| `CURSOR_DELTA` | `0x06` | 20 B | One-finger relative cursor movement |

Full layout, flags byte, and payload offsets in [`protocol/README.md`](protocol/README.md).

---

## Why not native pinch?

Two-finger pinch on the tablet is sent as `STYLUS_ZOOM`, but the Mac translates it into `Cmd+scroll` rather than a real `kCGEventTypeGesture` (rawValue 29) `magnify` event. The native gesture path is undocumented and silently dropped by `cgSessionEventTap` for apps that lack a private Apple entitlement (`com.apple.private.gesture-events`), even with Hardened Runtime + Apple Development cert. The `Cmd+scroll` fallback works universally in apps that map that combo to zoom (Krita, Preview, Affinity, Chrome, Safari, Figma). The flag `CGEventInjector.preferGestureEvent` is reserved for the day this changes; keep it `false`.

For the same reason, synthetic mouse-button events require a proper Apple Development cert + Hardened Runtime + entitlements file. An ad-hoc signed binary will move the cursor but not click. The signing recipe is below.

---

## Build and run

### Prerequisites

- macOS 13+ with Xcode 15+ command-line tools (`swift --version` ≥ 5.9)
- Android SDK + JDK 17 (Temurin recommended)
- An Apple Development certificate in the login keychain (find the identity with `security find-identity -v -p codesigning`)
- Android device with a stylus, USB debugging enabled
- ADB on `PATH` (the Mac app auto-discovers it; `which adb` should resolve)

### macOS server

```bash
cd macos
swift build -c release

# Copy the binary into the .app bundle, sign with your Development cert
cp .build/release/InkBridge build/InkBridge.app/Contents/MacOS/InkBridge
codesign --force --deep --options runtime \
  --entitlements InkBridge.entitlements \
  --sign "Apple Development: Your Name (XXXXXXXXXX)" \
  build/InkBridge.app

open build/InkBridge.app
```

On first launch macOS will prompt for **Accessibility** permission (System Settings → Privacy & Security → Accessibility). Without it the server runs but cannot inject events.

### Android client

```bash
cd android
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
  ./gradlew :app:installDebug
```

Then launch **InkBridge** from the app drawer.

### USB connection (recommended for lowest latency)

The Mac app auto-runs `adb reverse tcp:4545 tcp:4545` when it detects a connected device — the **USB** chip in the server window turns green. If it stays grey, run the command manually:

```bash
adb reverse tcp:4545 tcp:4545
```

Then on the Android side: pick **USB**, tap **Connect**.

### Wi-Fi connection

Make sure the phone and Mac are on the same network. Find the Mac's LAN IP (`ifconfig | grep 'inet 192'`), enter it on the **Wi-Fi** tab, tap **Connect**.

---

## Tests

Both platforms run tests entirely in-process — no real sockets, no real ADB, no real `CGEventPost`.

```bash
# macOS
cd macos && swift test

# Android
cd android && JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home \
  ./gradlew :app:testDebugUnitTest --no-daemon
```

The `protocol/test-vectors/*.hex` files are the canonical wire-format reference — both test suites round-trip them to confirm the encoder and decoder agree byte-for-byte.

---

## Latency budget

End-to-end stylus → cursor latency on USB sits around **8–14 ms** in normal operation, dominated by:

- Android batching: `MotionEvent.getHistoricalX/Y` flattened into per-sample frames, single-thread emit dispatcher.
- TCP `noDelay = true` (Nagle disabled) on both sides for the loopback path.
- macOS `MainActor` injection with a cached `AXIsProcessTrusted()` value (re-read only on app foreground; not on every frame).
- Latency tracker publishes at 10 Hz to keep SwiftUI off the hot path at 240 Hz sampling.

Wi-Fi adds the LAN round-trip — typically 2–5 ms on a clean 5 GHz network, much more on a saturated one.

---

## Status & limitations

- **Personal spike, not a product.** No CI, no installer, no signing automation.
- **Not notarized.** You must sign with your own Apple Development identity to inject clicks.
- **No native pinch.** See above; uses `Cmd+scroll` fallback.
- **One client at a time** on TCP. UDP accepts datagrams from any sender on the LAN — beware open ports.
- **Tab S7 (SM-T870) reference device.** Other Samsung tablets work; non-Samsung Androids untested. Vibrator behavior in particular varies wildly across OEMs.
- **macOS 13+ required.** Older versions have a different scroll-phase API surface.

---

## SDD trail

Every change to this project went through Spec-Driven Development. Proposals, specs, designs, and task lists live under [`openspec/changes/`](openspec/changes/). The `foundation` change documents the original architecture; subsequent changes (`fix-concurrency`, `fix-lifecycle`, `polish-tests`, `feature-ui-polish`) document each follow-up. Read the proposals first — they explain *why* before *how*.

---

## License

No license declared yet. Treat as **all rights reserved** until that changes. Do not redistribute the signed `.app` bundle — the entitlements and signing identity inside it are tied to the author's developer account.
