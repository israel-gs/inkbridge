# Spec: Android Stylus Capture

## Purpose

Defines how the Android client captures stylus input from the device hardware and transforms it into the inkbridge event model prior to serialization. The capture layer reads raw `MotionEvent` data — position, pressure, tilt axes, button state, hover/proximity transitions — and normalizes it to transport-ready values. This spec does NOT cover serialization (wire-protocol.md) or transport (transport.md).

---

## Requirements

### R1. Stylus-Only Capture

The capture layer MUST process only events whose tool type is `MotionEvent.TOOL_TYPE_STYLUS` or `MotionEvent.TOOL_TYPE_ERASER`. Events with tool type `TOOL_TYPE_FINGER`, `TOOL_TYPE_MOUSE`, or `TOOL_TYPE_UNKNOWN` MUST be ignored and MUST NOT produce any inkbridge frames.

#### Scenario: finger touch ignored
- **Given** the user places a finger on the capture surface
- **When** the MotionEvent is received with `getToolType(0) == TOOL_TYPE_FINGER`
- **Then** the capture layer MUST consume the event without producing a frame and MUST NOT pass it to the transport layer

#### Scenario: stylus event accepted
- **Given** the user touches the screen with an S Pen or any compatible stylus
- **When** the MotionEvent is received with `getToolType(0) == TOOL_TYPE_STYLUS`
- **Then** the capture layer MUST extract all relevant axes and produce an inkbridge frame

---

### R2. Position Normalization

The `x` and `y` position fields in the inkbridge frame MUST be normalized to the range [0.0, 1.0] relative to the dimensions of the capture surface view, not the full screen resolution.

- `x = event.getX(0) / view.width`
- `y = event.getY(0) / view.height`

Both values MUST be clamped to [0.0, 1.0] after division. Values outside this range that result from edge-contact jitter MUST be clamped, not dropped.

#### Scenario: center of screen
- **Given** a 1080×2400 display and the stylus touches the center (540, 1200)
- **When** the position is normalized
- **Then** the encoded `x` MUST equal `0.5` and `y` MUST equal `0.5` (within IEEE 754 f32 precision)

#### Scenario: clamping at edge
- **Given** the stylus reports x = −2.0 due to edge proximity
- **When** the position is normalized and clamped
- **Then** the encoded `x` MUST be `0.0`

---

### R3. Pressure Extraction

The capture layer MUST read `MotionEvent.AXIS_PRESSURE` via `event.getAxisValue(MotionEvent.AXIS_PRESSURE, 0)`.

- If the returned value is non-zero (hardware supports pressure), the `PRESSURE_PRESENT` flag (bit 0 of the flags byte) MUST be set and the value MUST be mapped to [0, 65535] (u16) by multiplying by 65535 and rounding to the nearest integer.
- If the returned value is exactly `0.0`, the flag MUST be clear and the `pressure` field MUST be `0x0000`.
- The raw axis value MUST be clamped to [0.0, 1.0] before mapping, to guard against driver bugs.

#### Scenario: full pressure (tip fully pressed)
- **Given** `AXIS_PRESSURE` returns `1.0`
- **When** the capture layer maps it
- **Then** `pressure = 65535 = 0xFFFF`, `PRESSURE_PRESENT = 1`

#### Scenario: no pressure sensor
- **Given** a device where `AXIS_PRESSURE` always returns `0.0` for every stylus event
- **When** the capture layer processes the event
- **Then** `pressure = 0x0000`, `PRESSURE_PRESENT = 0`

---

### R4. Tilt Extraction

The capture layer MUST read:
- `MotionEvent.AXIS_TILT` — altitude angle of the stylus from the surface plane, in radians [0, π/2].
- `MotionEvent.AXIS_ORIENTATION` — azimuth of the stylus projected onto the surface, in radians [−π, π].

From these two values, the capture layer MUST compute Cartesian tilt components:
- `tilt_x = sin(orientation) × tan(altitude)` — projected tilt in the X direction
- `tilt_y = cos(orientation) × tan(altitude)` — projected tilt in the Y direction

Each component MUST be multiplied by 100 and rounded to yield values in degrees × 100, clamped to [−9000, 9000] (i16 range).

If `AXIS_TILT` returns `0.0`, both `tilt_x` and `tilt_y` MUST be encoded as `0` and `TILT_PRESENT` MUST be clear.

If `AXIS_TILT` returns a non-zero value, `TILT_PRESENT` (bit 1 of flags) MUST be set.

#### Scenario: stylus perpendicular to surface
- **Given** `AXIS_TILT = 0.0` (stylus perfectly upright)
- **When** the capture layer computes tilt
- **Then** `tilt_x = 0`, `tilt_y = 0`, `TILT_PRESENT = 0`

#### Scenario: stylus tilted 45° toward positive Y
- **Given** `AXIS_TILT = π/4` (45°), `AXIS_ORIENTATION = 0` (pointing toward positive Y)
- **When** the capture layer computes tilt
- **Then** `tilt_x = round(sin(0) × tan(π/4) × 100) = 0`, `tilt_y = round(cos(0) × tan(π/4) × 100) = 100`, `TILT_PRESENT = 1`

---

### R5. Button State Capture

The capture layer MUST read the button state from `MotionEvent.getButtonState()`.

- If `MotionEvent.BUTTON_STYLUS_PRIMARY` is set, the `BUTTON_PRIMARY` flag (bit 3) MUST be set.
- If `MotionEvent.BUTTON_STYLUS_SECONDARY` is set, the `BUTTON_SECONDARY` flag (bit 4) MUST be set.
- Button state changes MUST produce a `STYLUS_BUTTON` frame when no position change is detected, and MAY also be reflected in the flags byte of concurrent `STYLUS_MOVE` frames.

#### Scenario: primary button pressed during move
- **Given** the stylus is moving with the primary barrel button held
- **When** a STYLUS_MOVE frame is emitted
- **Then** `BUTTON_PRIMARY` flag (bit 3) MUST be `1` in the frame's flags byte

#### Scenario: button released with no movement
- **Given** the primary button was pressed and is now released with the stylus stationary
- **When** the MotionEvent with action `ACTION_BUTTON_RELEASE` is received
- **Then** a `STYLUS_BUTTON` frame MUST be emitted with `BUTTON_PRIMARY = 0`

---

### R6. Hover and Proximity Events

The capture layer MUST handle hover and proximity transitions via `MotionEvent` actions:

- `ACTION_HOVER_ENTER` → emit a `STYLUS_PROXIMITY` frame with `entering = 0x01` and `HOVER` flag set
- `ACTION_HOVER_MOVE` → emit a `STYLUS_MOVE` frame with `HOVER` flag set; `pressure` MUST be `0` and `PRESSURE_PRESENT` MUST be clear
- `ACTION_HOVER_EXIT` → emit a `STYLUS_PROXIMITY` frame with `entering = 0x00` and `HOVER` flag clear

The capture layer MUST NOT produce `STYLUS_MOVE` frames with `HOVER = 1` and `pressure > 0` simultaneously.

#### Scenario: stylus approaches screen
- **Given** the stylus enters the hover zone without touching
- **When** the OS fires `ACTION_HOVER_ENTER`
- **Then** a `STYLUS_PROXIMITY` frame with `entering = 0x01` MUST be emitted within one frame cycle (≤ 8 ms at 120 Hz)

#### Scenario: hover move
- **Given** the stylus is hovering above the surface and moves
- **When** `ACTION_HOVER_MOVE` events arrive
- **Then** `STYLUS_MOVE` frames MUST be emitted with `HOVER = 1`, `pressure = 0`, `PRESSURE_PRESENT = 0`

---

### R7. Historical Motion Points

Android batches `MotionEvent` samples within a single event. The capture layer MUST process historical samples via `MotionEvent.getHistoricalAxisValue()` and emit one frame per historical sample before emitting the frame for the current sample.

- Historical samples MUST be emitted in ascending time order (index 0 is oldest).
- Each historical sample MUST have a timestamp derived from `MotionEvent.getHistoricalEventTime(pos)` converted to nanoseconds.

#### Scenario: batched event with 3 historical points
- **Given** a MotionEvent with 3 historical samples and 1 current sample
- **When** the capture layer processes the event
- **Then** it MUST emit 4 frames in order: historical[0], historical[1], historical[2], current — each with its own timestamp

---

### R8. Capture Surface Scope

The capture layer MUST capture stylus events ONLY within the designated capture surface view on the Android UI. Events that occur outside this view (e.g., in the connection controls area) MUST NOT produce inkbridge frames.

#### Scenario: stylus on connection UI area
- **Given** the stylus touches a button in the connection control panel
- **When** the MotionEvent fires
- **Then** no inkbridge frame MUST be emitted for that event

---

### R9. Non-Samsung Device Compatibility

The capture layer MUST NOT contain any code branches or feature detection specific to Samsung hardware. All axes MUST be read via standard Android MotionEvent APIs. If an axis is unsupported on a device, the MotionEvent API will return `0.0`, which the capture layer handles per R3 (pressure) and R4 (tilt).

#### Scenario: generic Android tablet without pressure
- **Given** a non-Samsung device where a stylus is recognized but `AXIS_PRESSURE` always returns `0.0`
- **When** the capture layer encodes the event
- **Then** `PRESSURE_PRESENT = 0`, `pressure = 0`, and all other fields encode normally without error
