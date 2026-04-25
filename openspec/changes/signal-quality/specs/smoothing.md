# Spec: predictive smoothing

## R1. One-Euro filter

The smoothing implementation MUST be a [One-Euro filter](https://gery.casiez.net/1euro/), parameterised by:

- `minCutoff` (Hz) — default `5.0` (tau ≈ 32 ms; aggressive enough to kill stylus jitter, too short to feel laggy)
- `beta` (unitless slope) — default `0.5` (cutoff climbs steeply under motion so fast strokes pass through)
- `dCutoff` (Hz) — default `1.0`

The filter MUST expose two operations:

- `filter(value: Float, timestampNs: UInt64) -> Float` — applies one filter step and returns the filtered value.
- `reset()` — clears internal state so the next `filter` call starts a fresh stream.

## R2. Per-axis instances

Two independent filter instances MUST be used, one per axis (X and Y). They MUST NOT share state.

## R3. Wiring

The filter MUST be applied to the normalized `[0,1]` X and Y of every `STYLUS_MOVE` frame **before** coordinate mapping. Other frame types (PROXIMITY, BUTTON, SCROLL, ZOOM, CURSOR_DELTA) MUST bypass the filter.

## R4. Reset triggers

Both axis filters MUST `reset()` on:

- Every `STYLUS_PROXIMITY` frame with `entering = 0x01` (stylus entering hover).
- Every change of `naturalSmoothingEnabled` from off to on.

## R5. Disable

When the user toggles smoothing off in settings, `processFrame` MUST short-circuit the filter call entirely. There MUST be no allocation, no syscall, no Bézier-style overhead when smoothing is off.

## R6. Determinism

Given the same `(minCutoff, beta, dCutoff)` and the same sequence of `(value, timestampNs)` inputs, `filter` MUST produce bit-identical outputs across runs.

## Scenarios

### Static input

**Given** filter is initialised with default parameters  
**And** the same value `0.5` is fed for 10 frames at 240 Hz  
**Then** the output of frame 10 MUST equal the input within `1e-6`.

### Step response

**Given** filter is initialised with default parameters  
**And** input jumps from `0.0` to `1.0` at frame 1  
**And** subsequent frames stay at `1.0` for 30 frames at 240 Hz  
**Then** the output at frame 30 MUST be ≥ `0.95` (filter has caught up).

### High-frequency jitter rejection

**Given** filter is initialised with default parameters  
**And** input alternates `0.500 ± 0.001` for 100 frames at 240 Hz  
**Then** the output peak-to-peak amplitude MUST be ≤ 50% of the input peak-to-peak amplitude.

### Realistic stroke pass-through

**Given** filter is initialised with default parameters  
**And** input ramps linearly from `0.0` to `1.0` over 60 frames at 240 Hz (a 250 ms stroke)  
**Then** the lag at the final frame (input minus output) MUST be ≤ `0.06`.

A shorter ramp would be unrealistic — 10 frames at 240 Hz is a 42 ms full-screen-width flick, not a stroke. The filter intentionally lags during the first ~5 samples while it estimates velocity; over realistic stroke lengths that startup cost is amortized to zero.
