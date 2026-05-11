# iOS Client Specification

> Canonical spec | Change: `ios-client` | Promoted: 2026-05-11

## Purpose

Defines the behavioral requirements for the InkBridge iPhone client — a wireless
trackpad and Express Keys remote over Wi-Fi. The iPhone has no stylus or pressure
sensor; this spec covers only the touch-routing, discovery, connection, Express Keys,
capture-from-Mac, settings, and lifecycle behaviors that the client MUST exhibit.
Wire protocol v1 is unchanged; the iOS client is a new consumer, not a revision.

---

## Named Constants

| Constant | Value | Used In |
|---|---|---|
| `DOUBLE_TAP_DRAG_WINDOW_MS` | 350 ms | Double-tap-drag activation window |
| `DOUBLE_TAP_DRAG_SPATIAL_TOLERANCE_PT` | 20 pt | Max distance between first-tap and second-tap-down |
| `PINCH_THRESHOLD_PT` | 10 pt | Min spread delta before classifying 2-finger as zoom vs. scroll |
| `DISCOVERY_PORT` | 4546 | UDP broadcast discovery port |
| `DISCOVERY_PROBE_INTERVAL_S` | 2 s | Interval between broadcast probe packets |
| `DISCOVERY_STALE_PRUNE_S` | 10 s | Age after which a non-responding host is removed from list |
| `DISCOVERY_REPLY_TIMEOUT_S` | 2 s | Max wait for discovery replies before showing empty-state |
| `RECONNECT_BACKOFF_SEQUENCE` | 0.5 s, 1 s, 2 s, 5 s (capped) | Successive delays on transient connection failure |
| `RECONNECT_ON_FOREGROUND_BUDGET_S` | 1 s | Max time to re-establish connection after app foregrounds |
| `EXPRESS_KEY_COUNT` | 6 | Buttons per Express Keys profile |

---

## Requirements

### Requirement: Local Network Permission

The iOS client SHALL declare `NSLocalNetworkUsageDescription` and
`NSBonjourServices = ["_inkbridge._udp"]` in `Info.plist` so that the system
Local Network permission prompt fires on first LAN traffic.

#### Scenario: First-launch permission prompt

- WHEN the app starts for the first time and issues any LAN UDP packet
- THEN the system Local Network permission dialog SHALL appear before the packet is sent
- AND the app SHALL NOT silently fail or crash if permission is denied

#### Scenario: Permission denied fallback

- GIVEN the user has denied Local Network permission
- WHEN the connection screen is displayed
- THEN the app SHALL show a visible warning explaining that discovery requires Local
  Network access
- AND manual IP entry SHALL remain functional

---

### Requirement: Discovery

The client SHALL discover running InkBridge servers on the local Wi-Fi by sending
a UDP broadcast probe (`INKB?`) to `255.255.255.255:DISCOVERY_PORT` and to the
subnet-directed broadcast address every `DISCOVERY_PROBE_INTERVAL_S`. Servers
responding with `INKB!` SHALL be shown in a discovered-hosts list. Any host that
has not responded within `DISCOVERY_STALE_PRUNE_S` SHALL be pruned from the list.

#### Scenario: Server auto-discovered

- GIVEN the Mac server is running on the same Wi-Fi network
- WHEN the connection screen becomes visible
- THEN the Mac server SHALL appear in the discovered-hosts list within
  `DISCOVERY_REPLY_TIMEOUT_S`

#### Scenario: No reply within timeout — empty state

- GIVEN no InkBridge server is reachable or broadcast is blocked
- WHEN `DISCOVERY_REPLY_TIMEOUT_S` elapses with no replies
- THEN the UI SHALL display "No servers found — enter IP manually" above the manual
  IP entry field
- AND the manual IP entry field SHALL remain visible and editable at all times

#### Scenario: Stale host pruned

- GIVEN a server appears in the discovered-hosts list
- WHEN that server stops responding and `DISCOVERY_STALE_PRUNE_S` elapses
- THEN the server SHALL be removed from the list without user action

#### Scenario: Tap to connect from list

- GIVEN at least one server is shown in the discovered-hosts list
- WHEN the user taps an entry
- THEN the host field SHALL populate with that server's IPv4 and the connect flow
  SHALL be triggered automatically

---

### Requirement: Manual IP Connection

The client SHALL allow the user to connect by entering a host IP address and port
manually. Manual entry SHALL take precedence over any auto-discovered host.

#### Scenario: Manual IP connect

- WHEN the user enters a valid host IP and port and taps Connect
- THEN the client SHALL attempt to open a UDP unicast connection to that IP:port
- AND settings SHALL persist the host and port for the next launch

#### Scenario: Manual overrides tapped host

- GIVEN the user previously tapped a discovered host (field shows its IP)
- WHEN the user clears the field and types a different IP
- THEN the manually entered IP SHALL be used for connection — the user-typed value wins

---

### Requirement: Connection State

The client SHALL present distinct UI states for: disconnected, connecting, connected,
and error/retry. The active host:port SHALL be shown while connected.

#### Scenario: Connecting indicator

- WHEN the client is attempting to connect to a host
- THEN a "Connecting…" indicator SHALL be visible and interactive controls other than
  Cancel SHALL be disabled

#### Scenario: Connected state

- GIVEN the client has successfully sent at least one event frame to the Mac
- WHEN the connection screen updates
- THEN the UI SHALL show "Connected to \<IP\>:\<port\>" and the canvas SHALL become
  interactive

---

### Requirement: 1-Finger Gestures

A single-finger drag on the capture canvas SHALL emit `CURSOR_DELTA (0x06)` frames
to move the macOS cursor. A single-finger tap (no movement) SHALL emit
`STYLUS_BUTTON (0x03)` for a left-click. A 2-finger tap SHALL emit
`STYLUS_BUTTON (0x03)` for a right-click.

#### Scenario: 1-finger drag → cursor motion

- GIVEN the client is connected
- WHEN the user drags one finger across the canvas
- THEN one or more `CURSOR_DELTA (0x06)` frames SHALL be emitted with dx/dy values
  proportional to finger displacement, at the natural rate of touch events

#### Scenario: 1-finger tap → left-click

- GIVEN the client is connected
- WHEN the user taps the canvas with one finger (no significant movement)
- THEN exactly one `STYLUS_BUTTON (0x03)` frame SHALL be emitted representing a
  left-click action

#### Scenario: 2-finger tap → right-click

- GIVEN the client is connected
- WHEN the user taps the canvas simultaneously with two fingers
- THEN exactly one `STYLUS_BUTTON (0x03)` frame SHALL be emitted representing a
  right-click action

---

### Requirement: 2-Finger Scroll and Zoom

A 2-finger drag on the canvas SHALL be classified as scroll (`STYLUS_SCROLL 0x04`)
or zoom (`STYLUS_ZOOM 0x05`) based on the dominant axis. Classification SHALL use
hysteresis: once a gesture is classified it SHALL NOT switch mid-gesture. A gesture
SHALL be classified as zoom only when the pinch-spread delta exceeds
`PINCH_THRESHOLD_PT` from the initial 2-finger separation; otherwise it SHALL be
classified as scroll.

#### Scenario: Translation-dominant → scroll

- GIVEN the client is connected and two fingers are placed on the canvas
- WHEN the fingers translate together without significant spread change
- THEN `STYLUS_SCROLL (0x04)` frames SHALL be emitted; no `STYLUS_ZOOM` frames SHALL
  be emitted in the same gesture

#### Scenario: Spread-dominant → zoom

- GIVEN the client is connected and two fingers are placed on the canvas
- WHEN the fingers spread apart or pinch by more than `PINCH_THRESHOLD_PT`
- THEN `STYLUS_ZOOM (0x05)` frames SHALL be emitted; no `STYLUS_SCROLL` frames SHALL
  be emitted in the same gesture

#### Scenario: Hysteresis — no mid-gesture switch

- GIVEN a 2-finger gesture has been classified as scroll
- WHEN the spread delta subsequently exceeds `PINCH_THRESHOLD_PT`
- THEN the gesture SHALL continue emitting `STYLUS_SCROLL (0x04)` — it SHALL NOT
  switch to `STYLUS_ZOOM (0x05)` until the gesture ends and a new one begins

---

### Requirement: Double-Tap-Drag

A double-tap-drag gesture SHALL initiate a drag-select on the Mac. The gesture is
recognized when a second tap-down lands within `DOUBLE_TAP_DRAG_WINDOW_MS` of the
first tap-up AND within `DOUBLE_TAP_DRAG_SPATIAL_TOLERANCE_PT` of the first tap. If
both conditions are met and the second touch continues moving, the client SHALL emit
continuous `CURSOR_DELTA (0x06)` frames with a logical "button held" state, equivalent
to a mouse drag.

#### Scenario: Double-tap-drag activates within window

- GIVEN the user lifts finger after a tap
- WHEN a second tap-down occurs within `DOUBLE_TAP_DRAG_WINDOW_MS` and within
  `DOUBLE_TAP_DRAG_SPATIAL_TOLERANCE_PT`
- AND the second finger continues moving without lifting
- THEN `CURSOR_DELTA (0x06)` frames SHALL be emitted continuously representing a
  held-button drag

#### Scenario: Double-tap-drag window missed — ordinary tap

- GIVEN the user lifts finger after a tap
- WHEN the second tap-down occurs after `DOUBLE_TAP_DRAG_WINDOW_MS` has elapsed
- THEN the second touch SHALL be treated as an independent new tap, not a drag-select

#### Scenario: Double-tap-drag spatial tolerance exceeded

- GIVEN the user lifts finger after a tap
- WHEN the second tap-down occurs within `DOUBLE_TAP_DRAG_WINDOW_MS` but more than
  `DOUBLE_TAP_DRAG_SPATIAL_TOLERANCE_PT` away from the first tap position
- THEN the gesture SHALL NOT be classified as double-tap-drag

---

### Requirement: Express Keys

The client SHALL display a sidebar of `EXPRESS_KEY_COUNT` configurable shortcut
buttons. Tapping a button SHALL emit a `KEY_EVENT (0x07)` frame encoding the
assigned macOS virtual key code and modifiers. Haptic feedback (medium intensity)
SHALL fire on each button tap.

#### Scenario: Express Key tap emits shortcut

- GIVEN the client is connected and Express Key slot 1 is configured as ⌘C
- WHEN the user taps slot 1
- THEN one `KEY_EVENT (0x07)` frame SHALL be emitted with key_code = `kVK_ANSI_C`,
  modifiers = Cmd bit set, action = tap

#### Scenario: Unassigned slot is inert

- GIVEN an Express Key slot has no shortcut assigned
- WHEN the user taps that slot
- THEN no `KEY_EVENT` frame SHALL be emitted and no error SHALL be shown

---

### Requirement: Express Key Profiles

The client SHALL support multiple named Express Key profiles. The user SHALL be able
to create, rename, delete, and switch between profiles. The active profile SHALL be
persisted and restored on next launch.

#### Scenario: Switch profile

- GIVEN two profiles exist: "Illustration" and "Video"
- WHEN the user selects "Video" in the profile picker
- THEN the Express Keys sidebar SHALL immediately reflect the "Video" profile's button
  assignments

#### Scenario: Profile persists across restart

- GIVEN the user has set "Video" as the active profile and configured its keys
- WHEN the app is terminated and relaunched
- THEN "Video" SHALL be the active profile and its key assignments SHALL be intact

---

### Requirement: Capture from Mac

The client SHALL provide a "Capture from Mac" flow that sends a `CAPTURE_REQUEST
(0x08)` frame to the server and waits for the server to respond with a captured key
combo, then assigns that combo to a selected Express Key slot.

#### Scenario: Successful capture

- GIVEN the client is connected and the user has selected an Express Key slot to assign
- WHEN the user initiates "Capture from Mac" and presses a key combo on the Mac keyboard
- THEN the server SHALL respond with the captured combo
- AND the client SHALL assign that combo to the selected slot and dismiss the capture modal

#### Scenario: Capture timeout / cancelled

- GIVEN the Capture from Mac modal is open
- WHEN the user taps Cancel or no response arrives within a reasonable timeout
- THEN the modal SHALL dismiss without modifying the Express Key slot
- AND the client SHALL NOT be left in a broken state

---

### Requirement: Settings Persistence

The client SHALL persist the following settings across app restarts and sideload
re-signing (same bundle ID): last-connected host IP, last-connected port, haptics
on/off, natural-scroll on/off, Express Keys sidebar edge (left/right), active profile
name, and all Express Key profile definitions.

#### Scenario: Settings survive restart

- GIVEN the user has changed host to `192.168.1.5`, port to `4545`, and disabled haptics
- WHEN the app is terminated and relaunched
- THEN the connection screen SHALL show `192.168.1.5:4545` and haptics SHALL be off

#### Scenario: Profile definitions survive re-signing

- GIVEN the user has created and saved profile "Video" with custom key assignments
- WHEN the app is re-signed with the same bundle ID (7-day cert renewal) and relaunched
- THEN profile "Video" and its assignments SHALL be present in the profile list

---

### Requirement: Reconnection and Lifecycle

The client SHALL tear down the UDP connection when the app enters the background and
SHALL auto-reconnect to the last host:port when the app returns to the foreground,
within `RECONNECT_ON_FOREGROUND_BUDGET_S`. On transient connection failure (not
user-initiated disconnect), the client SHALL retry using the backoff sequence
`RECONNECT_BACKOFF_SEQUENCE`.

#### Scenario: Background tears connection

- GIVEN the client is connected to a Mac server
- WHEN the user switches to another app or locks the screen
- THEN the UDP connection SHALL be closed and no further frames SHALL be sent

#### Scenario: Foreground auto-reconnects

- GIVEN the client was connected before going to background
- WHEN the app returns to the foreground
- THEN the client SHALL attempt to reconnect to the last host:port
- AND the connection SHALL be re-established within `RECONNECT_ON_FOREGROUND_BUDGET_S`
  (assuming the server is reachable)

#### Scenario: Transient failure triggers backoff retry

- GIVEN the client loses the connection unexpectedly (not user-initiated)
- WHEN the reconnection attempt fails
- THEN the client SHALL retry after 0.5 s, then 1 s, then 2 s, then 5 s (capped)
- AND the UI SHALL show a "Reconnecting…" indicator during each retry

---

### Requirement: Wire Protocol Conformance

The iOS client SHALL emit ONLY the following event types: `CURSOR_DELTA (0x06)`,
`STYLUS_BUTTON (0x03)`, `STYLUS_SCROLL (0x04)`, `STYLUS_ZOOM (0x05)`,
`KEY_EVENT (0x07)`, `CAPTURE_REQUEST (0x08)`. The client SHALL NOT emit
`STYLUS_MOVE (0x01)` or `STYLUS_PROXIMITY (0x02)`.

Every emitted frame SHALL conform to the fixed 16-byte header defined in
`protocol/README.md`: version = `0x01`, reserved byte = `0x00`, sequence
monotonically increasing per session, timestamp in nanoseconds from a monotonic clock.

#### Scenario: Round-trip canonical test vectors

- GIVEN the canonical test vectors in `protocol/test-vectors/` that correspond to
  event types the iOS client emits (`STYLUS_BUTTON`, `CURSOR_DELTA`, etc.)
- WHEN the iOS `BinaryStylusCodec` encodes a frame matching one of these vectors
- THEN the resulting byte sequence SHALL match the canonical `.hex` file exactly

#### Scenario: No stylus frames emitted

- GIVEN the client is connected and in use
- WHEN any number of touch gestures are performed on the canvas
- THEN no frame with `event_type = 0x01` (`STYLUS_MOVE`) or `event_type = 0x02`
  (`STYLUS_PROXIMITY`) SHALL ever be transmitted

---

### Requirement: Edge-Swipe and System Gesture Suppression

The canvas scene SHALL suppress iOS system edge-swipe gestures, persistent system
overlays, and the status bar so that touch input at screen edges and corners reaches
the canvas without triggering system navigation.

#### Scenario: Edge swipe does not dismiss canvas

- GIVEN the canvas is active and the client is connected
- WHEN the user performs a slow-swipe gesture starting from a screen edge
- THEN the gesture SHALL be intercepted by the canvas and SHALL NOT navigate to the
  app switcher or home screen

---

## Out of Scope (explicit)

- Stylus capture / pressure / tilt / hover / barrel button
- USB transport / `adb reverse` equivalents
- iPad-specific layout
- App Store distribution / App Sandbox / TestFlight
- Background-mode persistent connection
- Per-app pressure curves (no stylus → no pressure)
- Latency histogram / diagnostic overlay
- mDNS/Bonjour as the actual data-path discovery mechanism (`NSBonjourServices` is
  declared in `Info.plist` solely as a permission-prompt trigger)
