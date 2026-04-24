# Spec: User Interface

## Purpose

Defines the screen states, user-facing content, and interaction flows for both the Android client and the macOS server UIs. The Android UI consists of a connection screen and a capture surface. The macOS UI consists of a status window and an Accessibility onboarding flow. This spec covers observable UI behavior — what the user sees and can do in each state — not visual design or component implementation.

---

## Requirements

### R1. Android — Connection Screen States

The Android connection screen MUST display one of four connection states and update its controls accordingly.

| State          | Description                                                              |
|----------------|--------------------------------------------------------------------------|
| `DISCONNECTED` | Initial state. All controls are enabled. Connect button is enabled only when the host field is non-empty and format is valid. |
| `CONNECTING`   | Spinner or progress indicator visible. Transport controls and host/port fields MUST be disabled. Connect button replaced by Cancel button. |
| `CONNECTED`    | Active state. Transport info visible. Disconnect button visible. Capture surface is active and accepting stylus input. |
| `ERROR`        | Error message visible with the reason. Retry / Connect button re-enabled. Controls re-enabled. |

#### Scenario: initial launch
- **Given** the Android app launches for the first time
- **When** the connection screen appears
- **Then** the state MUST be `DISCONNECTED`, the host field MUST be empty, the Connect button MUST be disabled, and the transport selector MUST default to UDP (Wi-Fi)

#### Scenario: transition to CONNECTED
- **Given** the Android app is in `CONNECTING` state
- **When** the transport connection is established
- **Then** the state MUST transition to `CONNECTED` within 100 ms of the connection being confirmed, and the capture surface MUST become active

#### Scenario: connection error
- **Given** a TCP connection attempt is refused
- **When** the connection fails
- **Then** the state MUST transition to `ERROR` within 3 seconds, and the error message MUST indicate that the connection was refused (not a generic "something went wrong")

---

### R2. Android — Transport Selector

The Android connection screen MUST present a transport selector with exactly two options:
- **Wi-Fi (UDP)** — default
- **USB (TCP)**

Selecting **Wi-Fi (UDP)** MUST show the host IP field and port field.
Selecting **USB (TCP)** MUST show only the port field (host is fixed to `127.0.0.1` and MUST NOT be editable).

#### Scenario: USB transport selected
- **Given** the user selects "USB (TCP)" in the transport selector
- **When** the UI updates
- **Then** the host IP field MUST be hidden or clearly disabled, and a non-editable label showing `127.0.0.1 (via adb reverse)` MUST be visible

#### Scenario: Wi-Fi transport selected
- **Given** the user selects "Wi-Fi (UDP)"
- **When** the UI updates
- **Then** the host IP field MUST be visible and editable; the port field MUST be populated with the default port (4545)

---

### R3. Android — Host and Port Validation

The Connect button MUST remain disabled until all required fields pass validation:

- For UDP: host field is non-empty and contains a valid IPv4 address or hostname (no blank, no whitespace-only strings).
- For TCP: no host validation needed (fixed to `127.0.0.1`).
- Port field: must contain a valid integer in the range [1024, 65535].

Validation MUST be performed inline on every keystroke. The error state of each field MUST be visible independently.

#### Scenario: port out of range
- **Given** the user types `80` in the port field
- **When** the field is evaluated
- **Then** the port field MUST show an inline error ("Port must be between 1024 and 65535") and the Connect button MUST remain disabled

#### Scenario: valid host and port
- **Given** the user types `192.168.1.100` in the host field and `4545` in the port field
- **When** the fields are evaluated
- **Then** both fields MUST show no error and the Connect button MUST become enabled

---

### R4. Android — Capture Surface

The capture surface MUST:
- Be visible and occupy a clearly delineated area of the screen when the connection state is `CONNECTED`.
- Be inactive (not accept stylus input and not emit frames) when the connection state is not `CONNECTED`.
- Provide a visual affordance (e.g., a subtle border or background) indicating it is the active stylus input area.
- NOT show finger touch input or render ink strokes locally — it is a transparent forwarding surface only.

#### Scenario: capture surface inactive when disconnected
- **Given** the app is in `DISCONNECTED` or `ERROR` state
- **When** the user places the stylus on the capture surface area
- **Then** NO inkbridge frames MUST be emitted and the surface MUST not react visually to the input

#### Scenario: capture surface active when connected
- **Given** the app is in `CONNECTED` state
- **When** the user draws with the stylus on the capture surface
- **Then** STYLUS_MOVE frames MUST be emitted for each motion event within the surface boundaries

---

### R5. macOS — Status Window States

The macOS status window MUST display one of four states and update its controls accordingly.

| State          | Description                                                              |
|----------------|--------------------------------------------------------------------------|
| `IDLE`         | Server is not listening. Displayed when Accessibility permission is not granted. Start button hidden or disabled. Onboarding content visible. |
| `LISTENING`    | Server is bound and waiting. Transport type and port visible. Stop button visible. |
| `CONNECTED`    | A client is connected and sending frames. Client IP (for UDP) or "USB" label visible. Frame counter or last-event indicator visible. Stop button visible. |
| `ERROR`        | Transport error occurred. Error reason visible. Retry button visible.    |

#### Scenario: launch with Accessibility permission already granted
- **Given** the macOS app launches and `AXIsProcessTrusted()` returns `true`
- **When** the status window appears
- **Then** the state MUST be `LISTENING`, the port MUST be displayed, and no Accessibility onboarding content MUST be visible

#### Scenario: client connects
- **Given** the server is in `LISTENING` state
- **When** a UDP datagram arrives from a client IP
- **Then** the state MUST transition to `CONNECTED` and the client IP address MUST be displayed in the status window

---

### R6. macOS — Accessibility Onboarding Flow

The macOS app MUST present an onboarding UI when Accessibility permission is not granted. The onboarding MUST:

1. Explain in plain language why Accessibility is required (to inject tablet events for drawing apps).
2. Provide a button labeled "Open Accessibility Settings" that opens `System Settings > Privacy & Security > Accessibility` directly via `NSWorkspace.open(URL(...))`.
3. After the user returns to the app, automatically detect when permission is granted (via polling at ≤ 2-second intervals) and transition to `LISTENING` without requiring a restart.
4. NOT display any transport controls or status information while in this state.

#### Scenario: open Accessibility Settings button
- **Given** the Accessibility onboarding screen is visible
- **When** the user clicks "Open Accessibility Settings"
- **Then** macOS System Settings MUST open on the Accessibility section within 1 second

#### Scenario: auto-detect permission grant
- **Given** the Accessibility onboarding screen is visible
- **When** the user grants permission in System Settings
- **Then** within 2 seconds, the onboarding UI MUST disappear and the status window MUST show the `LISTENING` state automatically

#### Scenario: permission denied silently
- **Given** the user opens System Settings and closes it without granting permission
- **When** the app polls `AXIsProcessTrusted()`
- **Then** the app MUST remain in the onboarding state and MUST NOT transition to `LISTENING`

---

### R7. macOS — No Injection Before Permission

The macOS status window MUST display a clear indicator (text or icon) when the server is NOT injecting events due to missing Accessibility permission. The indicator MUST be distinct from the `ERROR` state — it MUST communicate "waiting for permission" rather than "something went wrong".

#### Scenario: permission missing indicator
- **Given** the macOS app is in the `IDLE` state due to missing permission
- **When** the user views the status window
- **Then** the UI MUST display text to the effect of "Accessibility permission required" and MUST NOT display any connection-related status

---

### R8. Android — Disconnect Action

When in the `CONNECTED` state, the Android UI MUST provide a clearly labeled Disconnect button. Tapping it MUST:

1. Close the transport connection immediately.
2. Transition the state to `DISCONNECTED`.
3. Re-enable all connection controls.

#### Scenario: user disconnects manually
- **Given** the app is in `CONNECTED` state
- **When** the user taps the Disconnect button
- **Then** the transport connection MUST be closed within 500 ms, the state MUST become `DISCONNECTED`, and the Connect button MUST be re-enabled

---

### R9. macOS — Stop Action

When in the `LISTENING` or `CONNECTED` state, the macOS status window MUST provide a Stop button. Tapping it MUST:

1. Close any active client connection.
2. Unbind the transport socket.
3. Transition the state to `IDLE`.

The server MUST NOT automatically restart listening after being stopped. The user MUST take an explicit action to start again.

#### Scenario: stop while client connected
- **Given** the server is in `CONNECTED` state with an active TCP client
- **When** the user clicks Stop
- **Then** the TCP connection MUST be closed, the socket unbound, and the state MUST become `IDLE` within 500 ms

---

### R10. Both Platforms — No Persisted Settings

In this change, NEITHER the Android app NOR the macOS server MUST persist any user settings (host, port, transport choice) between launches. All fields MUST reset to their default values on every launch.

This is an explicit constraint for the foundation spike, not an oversight. Persistence is deferred.

#### Scenario: Android relaunch
- **Given** the user previously connected with host `10.0.0.5` and port `9000`
- **When** the app is relaunched
- **Then** the host field MUST be empty and the port field MUST show the default `4545`
