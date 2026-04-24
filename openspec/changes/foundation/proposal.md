# Proposal: foundation

## Intent

Establish the end-to-end spike-foundation for inkbridge: an S Pen stroke on a Samsung (or any Android) device moves a cursor on macOS, carrying real pressure and tilt, over either Wi-Fi (UDP) or USB (TCP via `adb reverse`). This change exists to prove the critical path — stylus capture, versioned binary wire format, dual transport, and native tablet-event injection on macOS — before layering discovery, reconnection, telemetry, pairing, or UX polish on top. Everything built here is load-bearing for every future change, so the wire format and the injection strategy must be right on the first pass.

## Scope

### In scope

- Binary wire protocol with a fixed little-endian header, a version byte as the first byte for forward compatibility, and nanosecond (u64) timestamps for future jitter measurement.
- A single payload format shared by both transports: UDP over Wi-Fi and TCP over USB (via `adb reverse tcp:PORT tcp:PORT`).
- Android client (Kotlin + Jetpack Compose) capturing stylus `MotionEvent` including position, pressure, tilt (x/y), buttons, and hover/proximity transitions.
- macOS server (Swift + SwiftUI) consuming events and injecting them via `CGEventPost` using `kCGTabletEventType` and `kCGTabletProximityEventType`, carrying pressure and tilt fields.
- Manual IP entry on Android (typed host + port) as the only discovery mechanism for this change.
- Decent, production-quality UI from day 1 on both sides: Android connection screen (transport selector, IP/port, connection state, capture surface), macOS status window with onboarding for the Accessibility permission prompt.
- Support for non-Samsung Android devices: when hardware lacks pressure or tilt, fields are encoded as 0 / constant, and the protocol does not branch on vendor.

### Out of scope

- mDNS / Bonjour discovery — deferred; manual IP is sufficient to validate the critical path and keeps the foundation focused on transport + injection.
- Auto-reconnection and connection resilience — deferred; a manual reconnect from the UI is acceptable for the spike.
- Multi-display targeting and display mapping — deferred; the foundation targets the main display only.
- Encryption and pairing — deferred; the wire format reserves room but the spike runs in the clear on trusted networks / USB.
- Gestures, palm rejection, on-canvas UI — deferred; only raw stylus events are transmitted.
- Latency telemetry UI and dashboards — deferred; the nanosecond timestamp is wired in but not yet visualized.
- Persisted settings and multi-host history — deferred; the Android app can forget the IP on relaunch for now.

## Affected modules

- `android/` — Kotlin + Jetpack Compose client. Hosts the UI (connection screen, capture surface), the stylus capture layer, the transport clients (UDP + TCP), and the serializer for the wire format. Structured along clean-architecture lines: `domain/` (stylus event model, transport port), `data/` (UDP and TCP transport adapters, binary codec), `ui/` (Compose screens and view models).
- `macos/` — Swift + SwiftUI server. Hosts the status UI, the Accessibility onboarding flow, the transport listeners (UDP socket + TCP listener), the decoder, and the `CGEventPost` injector. Structured as `domain/` (stylus event model, injector port), `transport/` (UDP and TCP listeners + decoder), `injection/` (`CGEventPost` adapter with tablet fields), and SwiftUI views at the edge.
- `protocol/` — language-neutral specification of the wire format. A single source of truth that both `android/` and `macos/` implement against. Contains the header layout, field widths, endianness, version semantics, event-type enum, and a conformance checklist. No code — just the spec plus, optionally, test vectors.

## Approach

The architectural spine is: **stylus input on Android → versioned binary frame → one of two transports → decoder on macOS → `CGEventPost` with tablet fields**. Every module sits on one side of that spine, and the wire format in `protocol/` is the contract between them. Both clients apply clean-architecture layering so the transport and the injection mechanism are adapters behind ports — that way swapping UDP for QUIC later, or `CGEventPost` for a DriverKit-based path, is a localized change. The Android side separates domain from capture (`MotionEvent` is Android-specific and stays in `data/`), and the macOS side keeps `CGEventPost` behind an `Injector` port so the domain never imports CoreGraphics.

The wire format is binary, little-endian, with a fixed header whose first byte is the protocol version. After the version byte come event type, flags (buttons, hover/proximity, pressure-present, tilt-present), a nanosecond monotonic timestamp (u64), and a payload sized per event type. The same bytes travel over UDP (loss-tolerant, ordered-enough for input events at 120–240 Hz) and TCP (lossless, used when the user prefers USB). This is locked decision #3: one codec, two transports. The UDP path targets lowest latency on Wi-Fi; the TCP-over-USB path targets zero-drop, ~1 ms hop when connected via cable and `adb reverse tcp:4545 tcp:4545` is set up. Latency budget per hop (to document precisely in design): Android capture → serialize (< 0.5 ms), wire (< 2 ms UDP on good Wi-Fi, < 1 ms USB), decode → inject (< 0.5 ms). Total goal: < 4 ms wire-to-screen, well under Astropad's typical figures.

On macOS, injection uses `CGEventPost` with `kCGTabletEventType` and `kCGTabletProximityEventType` — this is locked decision #4, and avoids DriverKit entirely for the spike. Pressure and tilt (locked decision #5) are set via the tablet event fields so that drawing apps like Procreate-for-Mac-equivalents, Photoshop, and Clip Studio Paint see real stylus data rather than mouse events. The cost is that the macOS app must prompt the user for Accessibility permission on first run — the SwiftUI status window owns that onboarding.

On Android, we capture at the Compose `pointerInput` layer but read raw `MotionEvent` for the stylus axes (`AXIS_PRESSURE`, `AXIS_TILT`, `AXIS_ORIENTATION`, tool type, button state, hover actions). This means non-Samsung devices (locked decision #8) work without code branches: missing axes simply report their default (0 for pressure, 0 for tilt), and the protocol transports them unchanged. UI quality (locked decision #6) means the connection screen is a real SwiftUI-caliber Compose screen with transport choice, validation, state, and a capture surface — not a debug textbox.

Sequence diagrams for the handshake (transport selection → connect → first event) and for the steady-state event stream belong in the design document, not here.

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `CGEventPost` with tablet fields is undocumented enough that some target apps ignore pressure/tilt | Core value proposition (real stylus feel) fails silently | Validate against at least two real drawing apps during the spike; document which fields each app reads; keep the injector behind a port so a DriverKit path remains an option later |
| Wire-format v1 locks in a mistake (wrong field order, insufficient flag space, no room for extensions) that forces a breaking change | Every future client/server drift across versions | Version byte is the first byte; reserve flag bits and a trailing optional-extension region; write test vectors into `protocol/` so both sides conform exactly |
| UDP packet loss or reordering on flaky Wi-Fi causes visible stroke artifacts | User perceives inkbridge as "laggy" or "glitchy" — worse than Astropad | Include a monotonic sequence number alongside the nanosecond timestamp so the macOS side can drop out-of-order stale samples; USB path via TCP is always available as fallback; design doc specifies drop policy |
| `adb reverse` requires developer-mode setup that confuses non-technical users | USB path becomes unusable in practice | Onboarding on the macOS app walks through `adb reverse` once; a later change can wrap this in a helper, but for the spike clear docs + a one-line command are acceptable |
| Accessibility permission dance on macOS is easy to get wrong (requires restart, silent denial) | First-run failure, user abandons | macOS status UI detects permission state live, shows explicit guidance, and does not attempt to inject until the permission is granted |

## Rollback plan

Greenfield spike. If the foundation proves unworkable — e.g. `CGEventPost` tablet fields are not honored by enough target apps, or the wire format needs a redesign after integration — we delete `android/`, `macos/`, and `protocol/`, and start a new change. The openspec change record for `foundation` stays in the repo for history so the next attempt inherits the lessons (what failed, what the measured latencies were, which apps ignored which fields). No user data, no production deployments, no migrations — rollback is a `rm -rf` plus an archive entry.

## Open questions

- Which specific UDP port do we default to, and do we use the same port for TCP so `adb reverse tcp:PORT tcp:PORT` is symmetric? (Leaning toward a single port like `4545` for both; confirm in design.)
- Do we emit a `HELLO` / version-handshake frame on connect, or does the first real event implicitly carry the version byte and that is enough? (Affects whether the macOS side can reject a mismatched client cleanly before injecting anything.)
- For the hover/proximity event, do we send it as a distinct event type or as a flag on the position event? (Affects how `kCGTabletProximityEventType` is driven on the macOS side.)
