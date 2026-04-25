# Design: signal-quality

## 1. Module layout

Three new files in `Domain/`, one new file in `Server/`, edits to two existing files in `Server/` and `Injection/`, edits to two SwiftUI files.

```
macos/Sources/InkBridgeCore/
├── Domain/
│   ├── OneEuroFilter.swift           NEW — pure value type, no Foundation.Date
│   ├── PressureCurve.swift           NEW — pure value type, no Foundation
│   └── LatencyHistogram.swift        NEW — pure helper + HistogramBin type
├── Server/
│   ├── CurveRegistry.swift           NEW — registry + CurveStore protocol
│   └── InkBridgeServer.swift         EDIT — wire smoothing into processFrame
└── Injection/
    └── CGEventInjector.swift          EDIT — apply curve transform to pressure
```

```
macos/Sources/InkBridge/
├── ServerViewModel.swift              EDIT — own toggles, expose chart data
└── StatusView.swift                   EDIT — settings sheet, histogram section
```

## 2. One-Euro filter

The classic Casiez/Roussel/Vogel 2012 algorithm. Two stages:

1. **Velocity low-pass** — filter the difference between consecutive samples through an EMA at fixed cutoff `dCutoff`.
2. **Adaptive cutoff** — derive a per-sample cutoff `f_c = minCutoff + beta · |dx_filtered|` and apply an EMA at that cutoff to the value itself.

```swift
public struct OneEuroFilter {
    public let minCutoff: Float
    public let beta: Float
    public let dCutoff: Float

    private var lastValue: Float?
    private var lastFilteredDerivative: Float = 0
    private var lastTimestampNs: UInt64?

    public init(minCutoff: Float = 1.0, beta: Float = 0.007, dCutoff: Float = 1.0)

    public mutating func filter(_ value: Float, timestampNs: UInt64) -> Float
    public mutating func reset()
}
```

`filter` is mutating because it owns its own state; the caller keeps two instances (one per axis).

### Why One-Euro and not EMA

Plain EMA (`y_n = α · x_n + (1 - α) · y_{n-1}`) requires picking one α: low α = stable cursor + lagging fast strokes; high α = responsive but jittery. One-Euro's adaptive α resolves this by checking the local velocity — at rest it filters aggressively, on fast strokes it relaxes. Empirically this is the filter every modern stylus driver uses (Apple Pencil, Surface Pen).

### Implementation notes

- `Float` not `Double` — the input is a `Float32` from the wire, and the output goes back into the same precision domain. No reason for double-precision.
- The implementation MUST NOT use `Foundation.Date` or `DispatchTime` — it takes the timestamp as `UInt64` ns from the caller for testability and determinism.
- Edge case: first sample has no `lastTimestampNs`, so dt is undefined. Implementation returns the input unmodified and stores state for the second sample onward.

## 3. PressureCurve (cubic Bézier)

```swift
public struct PressureCurve: Equatable, Codable {
    public let p1: SIMD2<Float>     // ∈ [0,1]²
    public let p2: SIMD2<Float>     // ∈ [0,1]²

    public init(p1: SIMD2<Float>, p2: SIMD2<Float>)

    public static let linear = PressureCurve(p1: [0.33, 0.33], p2: [0.67, 0.67])
    public static let soft   = PressureCurve(p1: [0.40, 0.10], p2: [0.85, 0.55])
    public static let hard   = PressureCurve(p1: [0.15, 0.45], p2: [0.60, 0.90])

    public func apply(_ raw: Float) -> Float
}
```

### Bézier evaluation

Standard cubic: `B(t) = (1-t)³·p0 + 3(1-t)²t·p1 + 3(1-t)t²·p2 + t³·p3` with `p0 = (0,0)`, `p3 = (1,1)`.

Since we input X and want Y, we solve `B_x(t) = raw` for `t`, then evaluate `B_y(t)`.

Solve: 4 iterations of Newton (`t_{n+1} = t_n - (B_x(t_n) - raw) / B_x'(t_n)`) seeded with `t = raw` (close enough for monotone curves). Bisection fallback if Newton diverges (it shouldn't for our valid p1.x ≤ p2.x constraint, but defensive).

Total cost: ~30 ns per call. Negligible vs `CGEventPost`.

## 4. CurveRegistry

```swift
public protocol CurveStore: AnyObject {
    func loadDefault() -> PressureCurve
    func saveDefault(_ curve: PressureCurve)
    func loadOverrides() -> [String: PressureCurve]
    func saveOverrides(_ overrides: [String: PressureCurve])
}

public final class CurveRegistry {
    private let store: CurveStore
    private(set) var defaultCurve: PressureCurve
    private(set) var overrides: [String: PressureCurve]

    public init(store: CurveStore)

    public func curve(for bundleId: String?) -> PressureCurve
    public func setOverride(_ curve: PressureCurve, for bundleId: String)
    public func removeOverride(for bundleId: String)
    public func setDefault(_ curve: PressureCurve)
}
```

`UserDefaultsCurveStore: CurveStore` is the production impl; tests use an `InMemoryCurveStore`.

## 5. FrontmostAppDetector

`@MainActor` class that subscribes to `NSWorkspace.didActivateApplicationNotification` and stores `app.bundleIdentifier`. Polls once at init for the current value. Exposes a synchronous `var currentBundleId: String?`.

This is the only object in this change that touches `NSWorkspace`. Its job is to keep the inject hot path syscall-free.

## 6. Wiring

### Smoothing wiring

`InkBridgeServer.processFrame` already destructures `STYLUS_MOVE` events to call `CoordinateMapper.map`. Insert smoothing here, *before* the mapping:

```swift
if case let .move(x, y, p, tx, ty) = event {
    let smoothed = smoothingEnabled
        ? (filterX.filter(x, timestampNs: arrivalNs),
           filterY.filter(y, timestampNs: arrivalNs))
        : (x, y)
    let sample = makeSample(frame: frame, x: smoothed.0, y: smoothed.1)
    point = CoordinateMapper.map(sample: sample, display: displayRect)
    lastPoint = point
}
```

Two filter instances live as `private var` on `InkBridgeServer`, reset on every `STYLUS_PROXIMITY entering=1` frame.

### Pressure-curve wiring

`CGEventInjector.inject(_ event:, at:)` resolves the curve via the registry and the detector:

```swift
let bundle = frontmostAppDetector.currentBundleId
let curve = curveRegistry.curve(for: bundle)
let transformedPressure = curve.apply(rawPressure)
```

The injector receives `curveRegistry` and `frontmostAppDetector` via `init`. Tests pass mock implementations.

## 7. Latency histogram

### Bucket helper

```swift
public struct HistogramBin: Equatable {
    public let rangeMs: ClosedRange<Double>
    public let count: Int
}

public func latencyHistogram(samples: [Double], buckets: Int) -> [HistogramBin]
```

Pure. Operates on raw ns samples (so the existing ring buffer of arrivalToInjectNs can feed it directly). Returns ranges in ms for display convenience.

To expose the raw samples, `LatencyTracker.Snapshot` gains:

```swift
public let arrivalToInjectSamplesMs: [Double]   // NEW — full sample list
```

This is a small allocation (`≤ 256 doubles`) on every `snapshot()` call. Acceptable because `snapshot()` is throttled to 10 Hz.

### Chart

`StatusView` adds a collapsible section using SwiftUI's native `Chart` (macOS 13+, available since `import Charts`). Bars are `BarMark(x: .value("ms", bin.midpointMs), y: .value("count", bin.count))`. Y axis hidden, X axis shows ticks at `0`, `max/2`, `max`.

## 8. Settings

`SettingsRepository` (renamed mental model — currently the settings live in `ServerViewModel` directly) gains three `@Published` toggles:

```swift
@Published var smoothingEnabled: Bool = true
@Published var showLatencyChart: Bool = false
@Published var pressureCurveOverridesByBundle: [String: PressureCurve] = [:]
```

Persisted via `UserDefaults` keys `signalq.smoothing`, `signalq.histogram`, `signalq.curves.json`.

## 9. Threading

- `OneEuroFilter` is a value type; the caller (server) holds two instances and calls them on `MainActor` (server is `@MainActor`).
- `PressureCurve.apply` is pure; safe from any actor.
- `CurveRegistry` is `@MainActor` because the editor UI mutates it on the main thread and `CGEventInjector.inject` reads it on the main thread (also `@MainActor`).
- `FrontmostAppDetector` is `@MainActor` (subscribes to AppKit notifications).
- `latencyHistogram` is pure; safe from any actor.

No new dispatch queues are introduced. No new actor boundaries are crossed.

## 10. Testing

| Module | Tests |
|--------|-------|
| `OneEuroFilter` | static input convergence, step response, jitter rejection ratio, fast-move pass-through, reset clears state |
| `PressureCurve` | identity for Linear preset, monotonicity, clamping at edges, persistence round-trip |
| `CurveRegistry` | override resolution, default fallback, persistence round-trip via mock store |
| `LatencyHistogram` | empty input, uniform input, monotone bin ranges, count conservation (sum of counts == samples.count) |
| `InkBridgeServer` (existing) | smoothing on/off short-circuits the filter, proximity-enter resets filters |
| `CGEventInjector` (existing) | curve transform applied for STYLUS_MOVE, bypassed when curve is Linear (optional optimisation) |

All tests pure, no real `CGEvent`, no `NSWorkspace`, no `UserDefaults`.

## 11. Migration

None. New keys default to safe values:
- `signalq.smoothing` defaults to `true` (smoothing on for new users).
- `signalq.histogram` defaults to `false` (chart hidden).
- `signalq.curves.json` defaults to empty (Linear curve everywhere).

Existing users on a previous build see no change to behaviour until they touch settings, except that smoothing is on for them (which is the desired default — if it feels wrong, one click to disable).

## 12. Performance budget

| Operation | Budget | Measured (target) |
|-----------|--------|-------------------|
| `OneEuroFilter.filter` (one axis) | ≤ 200 ns | TBD |
| `PressureCurve.apply` | ≤ 100 ns | TBD |
| `latencyHistogram` (256 samples, 12 buckets) | ≤ 50 µs (called at 10 Hz) | TBD |
| Chart redraw | ≤ 5 ms / frame | TBD |

Inject hot path overhead added by this change: ≤ 0.5 µs per frame (filter × 2 + curve × 1). At 240 Hz that's 0.12 ms / second of MainActor time — invisible.
