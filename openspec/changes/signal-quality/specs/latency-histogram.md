# Spec: latency histogram in StatusView

## R1. Source data

The histogram MUST consume `LatencyTracker.Snapshot` published by `InkBridgeServer` via the existing `@Published var latency`. No new latency-tracking code path is introduced.

## R2. Histogram bucket helper

A pure function `latencyHistogram(samples: [Double], buckets: Int) -> [HistogramBin]` MUST live in `Domain/LatencyHistogram.swift` and:

- Bucket `arrivalToInjectNs` samples into `buckets` equal-width bins covering `[0, max]` where `max` is the maximum sample.
- Return one `HistogramBin(rangeMs: ClosedRange<Double>, count: Int)` per bucket in ascending order.
- Be pure: same input → same output, no side effects, no time access.

`buckets` MUST default to `12`.

## R3. UI placement

`StatusView` MUST gain a collapsible "Latency" section between the stats grid and the help row, hidden by default. The section MUST contain:

- A header row with three labels: `p50`, `p95`, `p99` showing `arrivalToInjectP50Ms`, `arrivalToInjectP95Ms`, `arrivalToInjectP99Ms` formatted to one decimal place.
- A `Chart` from SwiftUI Charts rendering the bins as `BarMark` with X = bin midpoint (ms), Y = count.
- A small caption noting "Mac-internal arrival → inject latency. Cross-device clock skew not shown."

When `latency.samples == 0` the chart MUST show an empty-state message ("No samples yet").

## R4. Performance

The chart MUST refresh at most every 100 ms even if `latency` updates faster. `InkBridgeServer` already throttles `latency` publishing to ~10 Hz; the chart MUST NOT add a faster refresh.

## R5. Settings toggle

Settings MUST expose "Show latency chart" as a switch. When off, the section MUST be removed from the view hierarchy entirely (not just hidden), so its `Chart` does not consume MainActor time.

## Scenarios

### Empty input

**Given** `samples = []`  
**When** `latencyHistogram(samples:buckets:12)` is called  
**Then** the result MUST be a 12-element array with `count == 0` in every bin.

### Uniform input

**Given** `samples = [1, 1, 1, 1]` (ns)  
**When** `latencyHistogram(samples:buckets:4)` is called  
**Then** the result MUST contain exactly 4 in one bin and 0 in the rest.

### Range monotonic

**Given** any non-empty `samples`  
**When** the helper is called  
**Then** consecutive bins MUST have strictly increasing `lowerBound` and the last bin's `upperBound` MUST equal the maximum sample (in ms).
