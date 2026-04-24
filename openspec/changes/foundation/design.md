# Design: foundation

## 1. Module layout

### 1.1 `android/` — Kotlin + Jetpack Compose

Clean architecture: `domain` has no Android imports; `data` owns `MotionEvent` and sockets; `ui` owns Compose.

```
android/
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/dev/inkbridge/android/
│       │   ├── InkbridgeApplication.kt
│       │   ├── domain/
│       │   │   ├── model/
│       │   │   │   ├── StylusEvent.kt          // pos, pressure, tilt, buttons, phase
│       │   │   │   ├── StylusPhase.kt          // enum: HOVER, DOWN, MOVE, UP, PROX_IN, PROX_OUT, BUTTON
│       │   │   │   └── ConnectionState.kt      // Idle, Connecting, Connected, Error(msg)
│       │   │   ├── port/
│       │   │   │   ├── Transport.kt            // connect/send/close; suspend interface
│       │   │   │   └── StylusCodec.kt          // encode(StylusEvent): ByteArray
│       │   │   └── usecase/
│       │   │       └── StreamStylus.kt         // accepts Flow<StylusEvent>, writes to Transport
│       │   ├── data/
│       │   │   ├── codec/
│       │   │   │   └── BinaryStylusCodec.kt    // little-endian ByteBuffer; wire format v1
│       │   │   ├── capture/
│       │   │   │   └── MotionEventMapper.kt    // MotionEvent → StylusEvent (AXIS_*, tool type)
│       │   │   └── transport/
│       │   │       ├── UdpTransport.kt         // DatagramSocket, non-blocking
│       │   │       └── TcpTransport.kt         // Socket, TCP_NODELAY=true
│       │   └── ui/
│       │       ├── theme/                      // Material 3 tokens
│       │       ├── connection/
│       │       │   ├── ConnectionScreen.kt     // transport selector, host/port, state
│       │       │   └── ConnectionViewModel.kt
│       │       └── capture/
│       │           ├── CaptureSurface.kt       // full-screen pointerInput + raw MotionEvent
│       │           └── CaptureViewModel.kt
│       └── res/
└── settings.gradle.kts
```

Responsibility notes:

- `domain` — pure Kotlin. No `android.*`, no `java.net.*`. Holds the event model and ports.
- `data/capture` — only place `MotionEvent` is allowed.
- `data/transport` — only place `java.net.*` / `DatagramSocket` / `Socket` is allowed.
- `data/codec` — the canonical wire-format implementation. Mirrors `protocol/`.
- `ui` — Compose only, talks to view models; view models talk to use cases.

### 1.2 `macos/` — Swift + SwiftUI

```
macos/
├── Package.swift
├── Sources/
│   ├── InkBridge/                              // @main SwiftUI app
│   │   ├── InkBridgeApp.swift
│   │   └── ContentView.swift
│   └── InkBridgeCore/
│       └── InkBridgeCore.swift                 // domain/transport/injection (importable by tests)
└── Tests/
    └── InkBridgeCoreTests/
        └── InkBridgeCoreTests.swift
```

Responsibility notes (full structure, post-Phase 1):

- `Domain` — pure Swift. No `CoreGraphics`, no `Network`.
- `Transport` — only place `Network.framework` is imported.
- `Injection` — only place `CoreGraphics` + `ApplicationServices` are imported.
- `Views` — SwiftUI only.

### 1.3 `protocol/` — language-agnostic

```
protocol/
├── README.md                                   // high-level + byte layout + test vectors
├── test-vectors/
│   ├── move-with-pressure-tilt.hex
│   ├── proximity-enter.hex
│   ├── proximity-exit.hex
│   └── button-press.hex
└── conformance-checklist.md                    // both implementations tick each box (R1–R11)
```

No code. Both Android `BinaryStylusCodec.kt` and macOS `BinaryStylusCodec.swift` must round-trip every `.hex` vector byte-identical.

## 2. Wire protocol design

### 2.1 Constants

| Name | Value |
|------|-------|
| `VERSION` | `0x01` |
| Endianness | little-endian everywhere |
| Default port | `4545` (same for UDP and TCP) |

No magic bytes in every frame. The `version` byte at offset 0 is the receiver's first gate.

### 2.2 Fixed header (16 bytes)

| Offset | Size | Type | Field | Notes |
|--------|------|------|-------|-------|
| 0 | 1 | u8 | `version` | MUST be 1 for this change. First byte — receiver rejects before parsing anything else. |
| 1 | 1 | u8 | `event_type` | see table 2.3 |
| 2 | 1 | u8 | `flags` | bitfield; see table 2.4 |
| 3 | 1 | u8 | `_reserved` | MUST be `0x00` on send; receiver MUST ignore |
| 4 | 4 | u32 | `sequence` | LE, monotonic per-session counter, wraps at 2^32 |
| 8 | 8 | u64 | `timestamp_ns` | LE, monotonic nanoseconds from Android `System.nanoTime()` |

Total header: **16 bytes**.

### 2.3 Message types

| Value | Name | Purpose |
|-------|------|---------|
| `0x01` | `STYLUS_MOVE` | Stylus tip touching or hovering with position data. HOVER flag (bit 2) distinguishes hover from contact. |
| `0x02` | `STYLUS_PROXIMITY` | Stylus entered or left the proximity zone. `entering` payload byte is `0x01` for enter, `0x00` for exit. |
| `0x03` | `STYLUS_BUTTON` | Button state changed without movement. |

All other values reserved. Unknown types are dropped and counted in diagnostics.

### 2.4 Flags (u8)

| Bit | Name | Meaning when set |
|-----|------|-----------------|
| 0 | `PRESSURE_PRESENT` | The `pressure` payload field carries a real sensor value. |
| 1 | `TILT_PRESENT` | The `tilt_x` / `tilt_y` payload fields carry real sensor values. |
| 2 | `HOVER` | Stylus is hovering (not touching); tip distance > 0. |
| 3 | `BUTTON_PRIMARY` | Primary barrel button is pressed. |
| 4 | `BUTTON_SECONDARY` | Secondary barrel button is pressed. |
| 5–7 | (reserved) | MUST be `0` on send; receivers MUST ignore. |

### 2.5 STYLUS_MOVE payload (20 bytes, follows 16-byte header → total 36 bytes)

| Offset from payload start | Size | Type | Field | Encoding |
|---------------------------|------|------|-------|----------|
| 0 | 4 | f32 | `x` | LE, screen-normalized [0.0, 1.0] |
| 4 | 4 | f32 | `y` | LE, screen-normalized [0.0, 1.0] |
| 8 | 2 | u16 | `pressure` | LE, 0–65535 (0 when `PRESSURE_PRESENT` clear) |
| 10 | 2 | i16 | `tilt_x` | LE, degrees × 100, −9000..9000 |
| 12 | 2 | i16 | `tilt_y` | LE, degrees × 100, −9000..9000 |
| 14 | 2 | u16 | `_pad` | MUST be `0x0000`; receiver MUST ignore |
| 16 | 4 | — | `_reserved` | MUST be `0x00000000`; receiver MUST ignore |

### 2.6 STYLUS_PROXIMITY payload (4 bytes, follows 16-byte header → total 20 bytes)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `entering` | `0x01` = entering proximity; `0x00` = leaving |
| 1 | 3 | — | `_pad` | MUST be `0x000000`; receiver MUST ignore |

`HOVER` flag (bit 2) MUST be `1` when entering, `0` when leaving.

### 2.7 STYLUS_BUTTON payload (4 bytes, follows 16-byte header → total 20 bytes)

| Offset from payload start | Size | Type | Field | Description |
|---------------------------|------|------|-------|-------------|
| 0 | 1 | u8 | `buttons` | Bitfield mirroring bits 3–4 of header `flags`. |
| 1 | 3 | — | `_pad` | MUST be `0x000000`; receiver MUST ignore |

The `buttons` field MUST be consistent with bits 3–4 of `flags`; inconsistency → discard.

### 2.8 Hex example — `STYLUS_MOVE` with pressure and tilt

Concrete values: version=1, event_type=STYLUS_MOVE (0x01), flags=0x03 (PRESSURE_PRESENT|TILT_PRESENT),
_reserved=0x00, sequence=42, timestamp=8,000,000,000 ns, x=0.5, y=0.25, pressure=49151 (≈0.75×65535),
tilt_x=4500 (45.00°), tilt_y=-1800 (-18.00°).

```
Offset  Hex                                          Field
------  -------------------------------------------  -----
00      01                                           version = 1
01      01                                           event_type = STYLUS_MOVE
02      03                                           flags = PRESSURE_PRESENT | TILT_PRESENT
03      00                                           _reserved
04      2A 00 00 00                                  sequence = 42
08      00 50 D6 DC 01 00 00 00                      timestamp_ns = 8,000,000,000 ns
--- payload (20 bytes) ---
10      00 00 00 3F                                  x = 0.5 (IEEE 754 f32 LE)
14      00 00 80 3E                                  y = 0.25 (IEEE 754 f32 LE)
18      FF BF                                        pressure = 49151 (0xBFFF LE)
1A      94 11                                        tilt_x = 4500 (45.00°, 0x1194 LE)
1C      F8 F8                                        tilt_y = -1800 (-18.00°, 0xF8F8 LE... wait: -1800 = 0xF8F8)
1E      00 00                                        _pad
20      00 00 00 00                                  _reserved
```

Total: **36 bytes**. Parse order: version → event_type → flags → _reserved → sequence → timestamp → payload.

## 3. Transport selection logic

### 3.1 UI rule

The Android connection screen has a segmented control: **USB (TCP)** | **Wi-Fi (UDP)**. No auto-detect in this change — explicit choice removes ambiguity and matches the spike scope.

Validation:

- Host: IPv4 only (`\d{1,3}(\.\d{1,3}){3}`), or `127.0.0.1` when USB is selected.
- Port: default `4545`, editable, `1..65535`.
- "Connect" button disabled until valid.

### 3.2 USB path preconditions (shown in UI)

```
adb reverse tcp:4545 tcp:4545
```

The Android app shows this exact command in a copy-button tile under the USB choice. If TCP connect times out, the error message reminds the user to run it.

## 4. Sequence diagrams

### 4.1 Event streaming

```
Stylus        Capture        Codec         Transport       Listener       Decoder       Injector
  |             |              |               |               |              |              |
  |---hover---->| PROX_ENTER   |               |               |              |              |
  |             |------------->| encode        |               |              |              |
  |             |              |-------------->| send          |              |              |
  |             |              |               |-------------->|------------->| CGEventPost  |
  |             |              |               |               |              |  Prox(inRng) |
  |---move x N->| STYLUS_MOVE  |               |               |              |              |
  |---exit------>| PROX_EXIT    |               |               |              | Prox(outRng) |
```

The first frame on a new connection MUST be a real event frame (STYLUS_MOVE, STYLUS_PROXIMITY, or STYLUS_BUTTON). There is no handshake preamble — version compatibility is determined by the `version` byte in every frame header.

### 4.2 Accessibility permission flow (macOS first run)

```
App launch
   |
   v
AccessibilityGate.check()  --> AXIsProcessTrusted()
   |
   +-- granted ------> StatusWindow: "Listening on 4545"  (start listeners)
   |
   +-- denied -------> PermissionOnboardingView
                          |
                          | "Open System Settings"  --> opens Privacy > Accessibility
                          |
                          | user toggles Inkbridge on
                          |
                          | app observes trust change (poll every 1 s)
                          v
                       StatusWindow: "Listening on 4545"
```

Listeners do NOT start until granted.

## 5. Latency budget

End-to-end targets: **P50 ≤ 15 ms (USB)**, **P50 ≤ 30 ms (Wi-Fi)**. P99 ≤ 2× P50.

| Hop | Budget USB (ms) | Budget Wi-Fi (ms) | Notes |
|-----|-----------------|-------------------|-------|
| `MotionEvent` dispatch → `encode` | 0.5 | 0.5 | Compose `pointerInput` is already on the UI thread; map + flag-pack is trivial. |
| `encode` → `socket send` | 0.5 | 0.5 | `ByteBuffer` reuse, single `write`/`send`. |
| Wire | 1.0 | 8.0 | USB is ~1 ms RTT via `adb reverse`; Wi-Fi depends on AP, assume decent 5 GHz. |
| `socket recv` → `decode` | 0.5 | 0.5 | `Data` / `ByteBuffer` LE read; zero allocations on hot path. |
| `decode` → `CGEventPost` | 1.0 | 1.0 | `CGEventPost` returns fast; includes tablet field sets. |
| OS → target app | 2.0 | 3.0 | Out of our control; budgeted for truth. |
| **Total (our code)** | **3.5** | **10.5** | |
| **Total with OS** | **5.5** | **13.5** | Under P50 target. |

Headroom: ~10 ms USB, ~16 ms Wi-Fi to P50 target. Not yet measured — this change writes the timestamp but does not visualize it; the budget is the bar for the first benchmark run.

## 6. Error handling

| Condition | Policy |
|-----------|--------|
| TCP `connect` fails | Android: state → `Error(reason)`. User taps "Retry". No auto-retry. |
| TCP socket drops mid-session | Android: state → `Error("connection lost")`. Capture surface disabled. |
| UDP send throws | Same as TCP drop. UDP has no "drop" event, so only send-side errors trigger this. |
| macOS receives unknown `event_type` | Drop packet, `diagnostics.bad_type += 1`. |
| macOS sees `STYLUS_PROXIMITY` (exit) without prior enter | Drop silently. `CGEventPost` is idempotent for "out of range". |
| Out-of-order `sequence` on UDP | If `seq < last_seq`, drop per wire-protocol.md R9. |
| Accessibility revoked mid-session | Stop injecting, state → `Error("Accessibility revoked")`. Keep listening. |

All counters visible in macOS `DiagnosticsView` and Android connection screen footer. No persistence.

## 7. Architecture decisions (ADR-lite)

### ADR-01 — Binary, little-endian wire format (not JSON)

- **Decision**: Fixed-layout binary with little-endian fields, version byte first. 36-byte STYLUS_MOVE, 20-byte STYLUS_PROXIMITY and STYLUS_BUTTON.
- **Alternatives considered**: JSON lines, MessagePack, Protobuf, FlatBuffers.
- **Rationale**: JSON costs 5–10× the bytes and a parser allocation per event at 120–240 Hz — unacceptable for MTU headroom and GC pressure on Android. Protobuf/FlatBuffers bring tooling weight and a schema compiler for a format that is two structs. A hand-rolled binary format is ≤36 bytes, zero allocations on the hot path, and trivially verifiable with hex test vectors. Little-endian is native on ARM and x86.

### ADR-02 — Dual UDP + TCP on the same port (not TCP-only)

- **Decision**: Listen on both UDP and TCP on `4545`; Android picks per session.
- **Alternatives considered**: TCP-only (simpler), UDP-only (fastest), separate ports per transport.
- **Rationale**: TCP-over-USB via `adb reverse` gives zero-drop ~1 ms RTT and survives the entire session cleanly — ideal when tethered. UDP gives lowest latency over Wi-Fi and tolerates the occasional lost packet far better than TCP's head-of-line blocking. Same port keeps the `adb reverse` command symmetric (`tcp:4545 tcp:4545`) and keeps firewall guidance simple. One codec serves both.

### ADR-03 — `CGEventPost` with tablet fields (not DriverKit)

- **Decision**: `CGEventPost` with `kCGTabletEventType` / `kCGTabletProximityEventType`, setting `kCGTabletEventPointPressure`, `kCGTabletEventTiltX`, `kCGTabletEventTiltY` via `CGEventSetDoubleValueField`.
- **Alternatives considered**: DriverKit, IOHIDPostEvent (deprecated), third-party tablet drivers.
- **Rationale**: DriverKit requires an entitlement, code-signing gymnastics, and a system extension that needs user approval and a reboot — too much friction for a spike. `CGEventPost` requires only Accessibility permission, runs in-process, and carries real pressure and tilt to drawing apps that read those fields. If field acceptance turns out to be spotty (see Risk 1), the `Injector` port makes a DriverKit swap a later, localized change.

### ADR-04 — Manual IP entry (not mDNS)

- **Decision**: User types IP + port on Android; no discovery.
- **Alternatives considered**: mDNS/Bonjour, QR code pairing, USB-carried auto-connect.
- **Rationale**: The spike's goal is to prove the wire and the injection. Discovery is a separate concern with its own surface (permissions on Android 13+ for `NSD`, Bonjour registration on macOS, mismatched network segments). Shipping it here would double the scope. A later change adds mDNS on top of an already-working foundation.

### ADR-05 — Single fixed port `4545` (not configurable)

- **Decision**: Hard-code `4545` as the default; port is editable in UI for debugging but not persisted.
- **Alternatives considered**: Random ephemeral port advertised by mDNS, fully configurable with persistence.
- **Rationale**: `4545` is unprivileged, memorable, and unused by common services. Fixed default removes one variable from every bug report. The port field stays editable because sometimes `4545` is taken, but without persistence it resets each launch — keeping the UI honest about what's default.

## 8. Risks and unknowns

| # | Risk | Discovery path during implementation |
|---|------|--------------------------------------|
| 1 | `CGEventPost` tablet fields are silently ignored by some drawing apps (Procreate-for-Mac-equivalents, Photoshop, Clip Studio Paint). | Build a tiny manual-test checklist per app: open app, draw, verify pressure modulates brush. If an app ignores tilt, log which field via event taps (`CGEventTapCreate` on self) to confirm the field is set correctly; then the failure is app-side, not ours. |
| 2 | UDP on crowded 2.4 GHz Wi-Fi drops enough packets that strokes look chunky. | Implement the `sequence` drop-policy from day 1; diagnostics view counts dropped/out-of-order. Measurement comes for free; if drops > 1% the spike's UX tells us immediately. |
| 3 | Monotonic clocks drift between Android `System.nanoTime()` and macOS `mach_absolute_time()` in ways that break the timestamp-based latency view (later). | Timestamps are carried in every frame header; offset computation is deferred to a future change but the data is already there. |
| 4 | `adb reverse tcp:4545 tcp:4545` is forgotten by users and the USB path looks broken. | Error message on TCP connect timeout literally shows the command. Onboarding tile has copy-to-clipboard. |
| 5 | Accessibility permission grant on macOS requires the user to quit and relaunch on some OS versions. | Poll `AXIsProcessTrusted()` every 1 s; detect the grant live where possible, show "Quit and relaunch" fallback CTA on the onboarding view if polling doesn't pick up the grant within 10 s. |
| 6 | Non-Samsung Android stylus devices report only `AXIS_PRESSURE` without `AXIS_TILT`, confusing the flags. | `MotionEventMapper` sets `TILT_PRESENT=0` when the axis isn't present; codec writes zeros; macOS treats zero tilt as "tip straight up". No code branch per vendor. |
| 7 | Coordinate normalization ([0,1]) loses precision on very large Android displays vs. small macOS displays. | f32 gives ~23 bits of mantissa; across a 4K display that's sub-pixel. Revisit only if observed artifacts surface. |

---

**Top 3 architectural risks** (for the return envelope): tablet-field acceptance across target drawing apps (ADR-03), wire-format v1 locking in a mistake that forces a breaking change later (ADR-01), and Accessibility permission UX on macOS (ADR-03 consequence).

---

## Reconciliation notes (2026-04-23)

The following changes were made to align this design document with the specs (specs are authoritative under SDD):

1. **HELLO / HELLO_ACK handshake removed** — `transport.md R7` explicitly prohibits a HELLO handshake in this change. The design previously defined HELLO payload (§2.6), HELLO_ACK payload (§2.7), and a connection handshake sequence diagram (§4.1). All of these have been removed. The `Handshake.kt` use case and `HandshakeResponder.swift` use case have been removed from the module layouts. Error-handling rows for `HELLO_ACK` timeout and version mismatch in `HELLO_ACK` have been removed from §6. The first frame on any connection is now a real event frame per spec.

2. **Header size corrected from 12 to 16 bytes** — `wire-protocol.md R3` defines a 16-byte header with fields: version (1), event_type (1), flags (1), _reserved (1), sequence (4), timestamp_ns (8). The design had a 12-byte header with a different field layout (no `_reserved` byte, `flags` was u16, `sequence` was absent from the header). All sections (§2.2 header table, §2.5 payload offsets, §2.8 hex example) now reflect the correct 16-byte layout. The hex example has been regenerated from scratch to match `wire-protocol.md R10` exactly.

3. **Event type enum reduced to 3 types** — `wire-protocol.md R4` defines only `STYLUS_MOVE (0x01)`, `STYLUS_PROXIMITY (0x02)`, and `STYLUS_BUTTON (0x03)`. The design had 9 types: HELLO, HELLO_ACK, STYLUS_HOVER, STYLUS_DOWN, STYLUS_MOVE, STYLUS_UP, PROX_ENTER, PROX_EXIT, BUTTON. These have been collapsed per spec: hover is now the `HOVER` flag (bit 2) on a `STYLUS_MOVE` frame; proximity enter/exit is the `entering` byte in a `STYLUS_PROXIMITY` payload.

4. **Flags field corrected from u16 to u8** — The spec defines `flags` at offset 2 as 1 byte (u8), not a u16. The bit assignments have been updated accordingly.

5. **Sequence field moved to header** — Per `wire-protocol.md R3`, `sequence` is at header offset 4 (u32 LE), not in the event payload. The payload layouts no longer include a sequence field.

6. **Magic bytes removed from hot path** — The design had `MAGIC = 0x49 0x42 ("IB")` present on every event frame. Per spec, there are no magic bytes in the header — the `version` byte at offset 0 is the sole gate. Magic in the old design only appeared in HELLO/HELLO_ACK payloads, which are now removed.

7. **macOS scaffold changed from Xcode project to Swift Package** — Phase 0 scaffolding uses `Package.swift` (Swift Package Manager) instead of `Inkbridge.xcodeproj`. This removes the Xcode project format from the git repository and makes the macOS side buildable with `swift build` / `swift test` without Xcode. An Xcode project can be generated later via `open Package.swift` when UI work requires the simulator.
