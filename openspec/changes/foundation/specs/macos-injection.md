# Spec: macOS Event Injection

## Purpose

Defines how the macOS server decodes inkbridge frames and injects them into the system event stream as tablet events that drawing applications can interpret as real stylus input, carrying pressure and tilt data. Injection uses `CGEventPost` with `kCGTabletEventType` and `kCGTabletProximityEventType`. This spec covers the injector behavior, field mapping, Accessibility permission gating, and display coordinate mapping. It does NOT cover transport or frame parsing — those are defined in `transport.md` and `wire-protocol.md`.

---

## Requirements

### R1. Accessibility Permission Gating

The macOS server MUST NOT call `CGEventPost` for any event unless the application has been granted Accessibility access (Accessibility permission in System Settings > Privacy & Security > Accessibility).

- On launch, the server MUST check the permission state using `AXIsProcessTrusted()`.
- If permission is not granted, the server MUST surface the onboarding flow (see `ui.md R3`) and MUST enter the `IDLE` state rather than `LISTENING`.
- The server MUST poll or observe the permission state at an interval of no greater than 2 seconds while in the onboarding state, and MUST automatically transition to `LISTENING` once permission is granted without requiring an app restart.

#### Scenario: permission not granted on launch
- **Given** the macOS app launches for the first time without Accessibility permission
- **When** `AXIsProcessTrusted()` returns `false`
- **Then** the server MUST NOT bind any transport socket, MUST NOT post any CGEvents, and MUST display the Accessibility onboarding UI

#### Scenario: permission granted while app is running
- **Given** the app is displaying the Accessibility onboarding UI
- **When** the user grants Accessibility permission in System Settings and returns to the app within 2 seconds
- **Then** the app MUST detect the permission change and automatically transition to `LISTENING` state without a restart

---

### R2. STYLUS_MOVE Injection — Tablet Event

For each received `STYLUS_MOVE` frame (with `HOVER = 0`), the server MUST inject a `CGEvent` of type `kCGTabletEventType` via `CGEventPost(kCGHIDEventTap, event)`.

The following tablet event fields MUST be set:

| CGEvent Field                           | Source                                       | Notes                                               |
|-----------------------------------------|----------------------------------------------|-----------------------------------------------------|
| `kCGTabletEventPointX`                  | `x × displayWidth` (pixels)                  | Integer pixels on the main display                  |
| `kCGTabletEventPointY`                  | `y × displayHeight` (pixels)                 | Integer pixels on the main display (Y-down)         |
| `kCGTabletEventPointPressure`           | `pressure / 65535.0` (normalized float)      | Only when `PRESSURE_PRESENT = 1`; else `0.0`        |
| `kCGTabletEventTiltX`                   | `tilt_x / 9000.0` (normalized −1.0 to 1.0)  | Only when `TILT_PRESENT = 1`; else `0.0`            |
| `kCGTabletEventTiltY`                   | `tilt_y / 9000.0` (normalized −1.0 to 1.0)  | Only when `TILT_PRESENT = 1`; else `0.0`            |
| `kCGTabletEventPointButtons`            | Derived from `BUTTON_PRIMARY`, `BUTTON_SECONDARY` flags | Bit 0 = primary, bit 1 = secondary          |

Additionally, a synthetic mouse move event MUST be injected at the same coordinates so that host applications that also listen to `NSEvent` mouse move events track the cursor position. The mouse event MUST be injected after the tablet event.

#### Scenario: STYLUS_MOVE with pressure and tilt
- **Given** a STYLUS_MOVE frame with `x=0.5`, `y=0.5`, `pressure=32767`, `tilt_x=4500`, `tilt_y=0`, `PRESSURE_PRESENT=1`, `TILT_PRESENT=1`
- **When** the injector processes the frame on a 2560×1600 main display
- **Then** `kCGTabletEventPointX = 1280`, `kCGTabletEventPointY = 800`, `kCGTabletEventPointPressure ≈ 0.4999847`, `kCGTabletEventTiltX = 0.5`, `kCGTabletEventTiltY = 0.0`

#### Scenario: STYLUS_MOVE without pressure sensor
- **Given** a STYLUS_MOVE frame with `PRESSURE_PRESENT = 0` and `pressure = 0`
- **When** the injector processes the frame
- **Then** `kCGTabletEventPointPressure` MUST be set to `0.0`

---

### R3. STYLUS_MOVE Injection — Hover Event

For each received `STYLUS_MOVE` frame with `HOVER = 1`, the server MUST inject a `CGEvent` of type `kCGTabletEventType` but with pressure set to `0.0`. The cursor MUST still be updated to the normalized position.

#### Scenario: hover move injection
- **Given** a STYLUS_MOVE frame with `HOVER = 1` and `pressure = 0`
- **When** the injector processes the frame
- **Then** a tablet event MUST be posted with `kCGTabletEventPointPressure = 0.0` and cursor coordinates matching the frame's x/y

---

### R4. STYLUS_PROXIMITY Injection

For each received `STYLUS_PROXIMITY` frame, the server MUST inject a `CGEvent` of type `kCGTabletProximityEventType` via `CGEventPost(kCGHIDEventTap, event)`.

The following proximity event fields MUST be set:

| CGEvent Field                         | Value when entering                | Value when leaving |
|---------------------------------------|------------------------------------|--------------------|
| `kCGTabletProximityEventEnterProximity` | `1`                              | `0`                |
| `kCGTabletProximityEventPointerType`  | `1` (pen tip)                      | `1` (pen tip)      |
| `kCGTabletProximityEventDeviceID`     | Constant `0x0001` (synthetic)      | Constant `0x0001`  |

#### Scenario: proximity enter
- **Given** a STYLUS_PROXIMITY frame with `entering = 0x01`
- **When** the injector processes the frame
- **Then** a `kCGTabletProximityEventType` CGEvent MUST be posted with `kCGTabletProximityEventEnterProximity = 1`

#### Scenario: proximity exit
- **Given** a STYLUS_PROXIMITY frame with `entering = 0x00`
- **When** the injector processes the frame
- **Then** a `kCGTabletProximityEventType` CGEvent MUST be posted with `kCGTabletProximityEventEnterProximity = 0`

---

### R5. Display Coordinate Mapping

In this change, the injector targets the main display only. The macOS server MUST resolve the main display dimensions via `CGMainDisplayID()` and `CGDisplayBounds()` at server start time and cache them.

- The cached display bounds MUST be refreshed when a display configuration change notification is received.
- All coordinate mapping MUST use the cached main display width and height.
- Multi-display targeting is out of scope; the macOS server MUST always inject events on the main display.

#### Scenario: display resolution change
- **Given** the user connects or disconnects an external display, changing the main display resolution
- **When** the macOS server receives a `CGDisplayReconfigurationCallback`
- **Then** the cached display bounds MUST be updated within one reconfiguration callback cycle before the next injection occurs

---

### R6. Injector Port Isolation

The injector MUST be implemented behind an `Injector` protocol (port in the clean-architecture sense). The concrete `CGEventPost`-based implementation MUST be the only type that imports CoreGraphics. The domain module MUST depend only on the `Injector` protocol and MUST NOT import CoreGraphics directly.

#### Scenario: injector protocol boundary
- **Given** a decoded inkbridge stylus event arrives in the domain layer
- **When** the domain calls the injector
- **Then** the call MUST go through the `Injector` protocol; no CoreGraphics type MUST appear in the domain event model or use-case types

---

### R7. Injection Rate Limit

The injector MUST NOT inject more than one event per incoming frame. It MUST NOT buffer or batch frames for deferred injection. Each frame MUST be injected synchronously upon receipt (within the same event-processing iteration).

#### Scenario: 240 Hz input rate
- **Given** the Android device is sending STYLUS_MOVE frames at 240 Hz (one frame every ~4.17 ms)
- **When** the macOS server receives each frame
- **Then** each frame MUST trigger exactly one `CGEventPost` call within the same processing cycle, with no buffering or coalescing

---

### R8. Error Handling on Injection Failure

If `CGEventPost` returns an error or the event cannot be created (e.g., `CGEventCreateTabletPointerEvent` returns `nil`), the server MUST log the error internally and MUST continue processing subsequent frames. A single injection failure MUST NOT cause the server to disconnect the transport or change its connection state.

#### Scenario: CGEventPost fails transiently
- **Given** one call to `CGEventPost` fails
- **When** the next frame arrives
- **Then** the server MUST attempt to inject the next frame normally, and MUST NOT enter an error state or close the transport connection
