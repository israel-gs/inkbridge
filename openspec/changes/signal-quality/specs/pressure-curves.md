# Spec: per-app pressure curves

## R1. Curve type

A `PressureCurve` MUST be representable as four control points `(p0, p1, p2, p3)` of a cubic Bézier in the unit square, where `p0 = (0, 0)` and `p3 = (1, 1)` are fixed and `p1, p2` are user-editable in `[0, 1] × [0, 1]`.

The `apply(_ raw: Float) -> Float` operation MUST:

- Return `0.0` when `raw ≤ 0.0`.
- Return `1.0` when `raw ≥ 1.0`.
- Return a value in `[0, 1]` clamped, monotonically non-decreasing in `raw`, for any `raw ∈ [0, 1]`.

The Bézier MUST be evaluated by directly solving for `t` from `raw` (treating `raw` as the X coordinate, since `p0.x = 0` and `p3.x = 1` and the curve is monotone in X when `0 ≤ p1.x ≤ p2.x ≤ 1`). A 4-iteration Newton solver bounded by bisection is acceptable.

## R2. Named presets

Three named presets MUST ship:

| Name | `p1` | `p2` | Effect |
|------|------|------|--------|
| Linear | `(0.33, 0.33)` | `(0.67, 0.67)` | Identity (matches today's behaviour). |
| Soft | `(0.40, 0.10)` | `(0.85, 0.55)` | Lower mid-range pressure for fine line work. |
| Hard | `(0.15, 0.45)` | `(0.60, 0.90)` | Faster ramp into mid pressure for confident strokes. |

## R3. Registry

A `CurveRegistry` MUST hold:

- One default curve (used when no per-app override exists).
- A map `bundleIdentifier → PressureCurve` for overrides.

The registry MUST be persisted via an injected `CurveStore` protocol (concrete impl: `UserDefaults`-backed, JSON-encoded).

`CurveRegistry.curve(for: String?) -> PressureCurve` MUST return:

- The override for `bundleIdentifier` if one exists.
- The default curve otherwise.
- The default curve if `bundleIdentifier == nil`.

## R4. Frontmost app detection

A `FrontmostAppDetector` MUST cache `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` and refresh on `NSWorkspace.didActivateApplicationNotification`. Reading the cached value MUST be synchronous and MUST NOT issue a syscall.

## R5. Wiring

`CGEventInjector.inject(_ event:, at:)` MUST, for `STYLUS_MOVE` frames where the `pressure` field is non-zero, transform the pressure through the curve resolved for the current frontmost app **before** posting the tablet event. The transform MUST happen entirely on the MainActor where the injector runs.

When the resolved curve is the Linear preset (or `apply(raw) == raw` for all sampled inputs) the transform MAY be skipped as an optimisation, but the visible behaviour MUST be identical.

## R6. Configuration UI

The Mac settings sheet MUST allow:

- Picking a preset for any installed application.
- Editing the default curve.
- Resetting any per-app override back to the default.
- Listing existing overrides with the option to delete each.

## Scenarios

### Identity curve

**Given** the Linear preset is the default  
**And** no per-app override exists  
**When** raw pressure `0.5` is applied  
**Then** the output MUST equal `0.5` within `1e-4`.

### Per-app override

**Given** a Hard curve is registered for `org.kde.krita`  
**And** the frontmost app is `org.kde.krita`  
**When** raw pressure `0.3` is applied  
**Then** the output MUST be greater than `0.3`.

### Bundle identifier missing

**Given** the frontmost app has no `bundleIdentifier`  
**When** any pressure is applied  
**Then** the default curve MUST be used.

### Persistence round-trip

**Given** a registry with two overrides is saved via the store  
**When** a fresh registry is constructed from the same store  
**Then** the new registry MUST have the same default curve and the same two overrides.
