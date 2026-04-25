# Tasks: signal-quality

Strict TDD: every task that touches production code starts with a failing test.

## Phase 1 — Pure types (no dependencies, fully testable in isolation)

### 1.1 OneEuroFilter
- [ ] 1.1.1 Test: static input converges to itself
- [ ] 1.1.2 Test: step response catches up to ≥ 0.95 within 30 frames at 240 Hz
- [ ] 1.1.3 Test: high-frequency jitter is attenuated by ≥ 50%
- [ ] 1.1.4 Test: fast linear ramp has lag ≤ 0.1 at frame 10
- [ ] 1.1.5 Test: `reset()` clears `lastValue`, `lastFilteredDerivative`, `lastTimestampNs`
- [ ] 1.1.6 Implement `OneEuroFilter` in `Domain/OneEuroFilter.swift`

### 1.2 PressureCurve
- [ ] 1.2.1 Test: Linear preset is identity within 1e-4
- [ ] 1.2.2 Test: monotone non-decreasing for any preset over 100 sample points
- [ ] 1.2.3 Test: clamps to 0 for negative input, 1 for input > 1
- [ ] 1.2.4 Test: Codable round-trip preserves p1, p2 exactly
- [ ] 1.2.5 Implement `PressureCurve` in `Domain/PressureCurve.swift`

### 1.3 LatencyHistogram
- [ ] 1.3.1 Test: empty input returns 12 bins of count=0
- [ ] 1.3.2 Test: uniform input concentrates count in one bin
- [ ] 1.3.3 Test: bin ranges are monotonically increasing and contiguous
- [ ] 1.3.4 Test: sum of counts equals samples.count
- [ ] 1.3.5 Implement `latencyHistogram(samples:buckets:)` and `HistogramBin` in `Domain/LatencyHistogram.swift`

## Phase 2 — Registry + persistence

### 2.1 CurveStore protocol + InMemoryCurveStore
- [ ] 2.1.1 Define `CurveStore` protocol
- [ ] 2.1.2 Implement `InMemoryCurveStore` for tests

### 2.2 CurveRegistry
- [ ] 2.2.1 Test: `curve(for: nil)` returns default
- [ ] 2.2.2 Test: `curve(for: "org.kde.krita")` returns override when set
- [ ] 2.2.3 Test: `curve(for: "unknown")` returns default
- [ ] 2.2.4 Test: registry round-trips via mock store (init reads, mutations write)
- [ ] 2.2.5 Implement `CurveRegistry` in `Server/CurveRegistry.swift`

### 2.3 UserDefaultsCurveStore
- [ ] 2.3.1 Test: write+read round-trip via stub `UserDefaults`-like dictionary
- [ ] 2.3.2 Implement `UserDefaultsCurveStore` (production)

## Phase 3 — Wiring

### 3.1 Server-side smoothing
- [ ] 3.1.1 Test: `processFrame` with smoothing off does NOT call filter (verify via Mock)
- [ ] 3.1.2 Test: `processFrame` with smoothing on transforms x, y of MOVE frames
- [ ] 3.1.3 Test: PROXIMITY entering=1 resets both filters
- [ ] 3.1.4 Wire `OneEuroFilter` × 2 into `InkBridgeServer.processFrame`

### 3.2 FrontmostAppDetector
- [ ] 3.2.1 Test: detector returns initial bundle id at init
- [ ] 3.2.2 Test: detector updates cache on `didActivateApplicationNotification`
- [ ] 3.2.3 Implement `FrontmostAppDetector`

### 3.3 Pressure-curve transform in injector
- [ ] 3.3.1 Test: injector applies curve to MOVE frame pressure when curve is non-Linear
- [ ] 3.3.2 Test: injector skips transform (or applies identity) when curve is Linear
- [ ] 3.3.3 Test: injector uses default curve when frontmost bundle id is nil
- [ ] 3.3.4 Wire `CurveRegistry` + `FrontmostAppDetector` into `CGEventInjector.inject`

## Phase 4 — Latency tracker exposure

### 4.1 Snapshot includes raw samples
- [ ] 4.1.1 Test: snapshot's `arrivalToInjectSamplesMs` has length == count
- [ ] 4.1.2 Test: values are arrival-to-inject in ms
- [ ] 4.1.3 Add `arrivalToInjectSamplesMs` to `LatencyTracker.Snapshot`

## Phase 5 — UI

### 5.1 ServerViewModel exposes toggles
- [ ] 5.1.1 Add `smoothingEnabled`, `showLatencyChart`, `pressureCurveOverrides` to `ServerViewModel`
- [ ] 5.1.2 Persist via `UserDefaults`
- [ ] 5.1.3 Wire toggles into the server (smoothing) and injector (curves)

### 5.2 StatusView histogram section
- [ ] 5.2.1 Add collapsible "Latency" section
- [ ] 5.2.2 Header shows p50/p95/p99 (arrival → inject)
- [ ] 5.2.3 SwiftUI `Chart` with `BarMark` driven by `latencyHistogram` over `arrivalToInjectSamplesMs`
- [ ] 5.2.4 Empty-state message when `samples == 0`
- [ ] 5.2.5 Hidden entirely (not rendered) when `showLatencyChart == false`

### 5.3 StatusView settings sheet
- [ ] 5.3.1 Add gear button → `Settings` sheet
- [ ] 5.3.2 Toggle: "Smoothing"
- [ ] 5.3.3 Toggle: "Show latency chart"
- [ ] 5.3.4 Section: "Pressure curves" with default-curve picker (Linear/Soft/Hard) and per-app overrides list

## Phase 6 — Verification

- [ ] 6.1 Full test suite green: `swift test`
- [ ] 6.2 Manual smoke: launch app, draw in Krita, verify no regressions
- [ ] 6.3 Toggle smoothing on/off via settings; observe difference in cursor stability at hover
- [ ] 6.4 Switch frontmost app between Krita and Preview, verify per-app curves take effect
- [ ] 6.5 Open latency chart, confirm bars update at ~10 Hz with sane buckets
- [ ] 6.6 Build + sign + commit

## Out of scope (deferred)

- A graphical Bézier curve editor (this release ships with named-preset picker only; the curve type supports arbitrary p1/p2 but the UI does not let the user set them numerically).
- Per-app smoothing overrides (smoothing is global on/off in this release).
- Histogram time axis (live trend over last N seconds) — current chart is a snapshot only.
