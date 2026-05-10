import CoreGraphics
import Foundation

// MARK: - Touch phase

/// Mirrors `UITouch.Phase` without importing UIKit.
/// The canvas layer maps UITouch.Phase values to this enum before calling `TouchRouter`.
public enum TouchPhase: Equatable {
    case began
    case moved
    case ended
    case cancelled
}

// MARK: - TouchRouter

/// Pure-value-type touch state machine.
///
/// Converts a stream of `TouchSample + TouchPhase` events into `[StylusEvent]` events
/// that are sent to the Mac server.
///
/// # Design constraints
/// - MUST be a `struct`, not a class — ensures value semantics, simplifies testing.
/// - MUST use an injected `now: () -> TimeInterval` clock — NEVER call `Date()`,
///   `CACurrentMediaTime()`, `CFAbsoluteTimeGetCurrent()`, or any real timer inside here.
/// - Timer-based "armed window expired" check is the canvas layer's responsibility
///   (via `CADisplayLink` poke) — not this struct's. This struct stays purely reactive.
///
/// # State machine (7 states)
/// ```
/// idle
///   → oneFingerActive    (1 finger begins)
///   → twoFingerEvaluating (2nd finger begins while 1st is active, or 2 fingers simultaneous)
///
/// oneFingerActive
///   → idle               (finger ended: tap or drag complete)
///   → twoFingerEvaluating (2nd finger joins)
///   → doubleTapDragArmed (IMPOSSIBLE from here; see doubleTapDragArmed below)
///   → doubleTapDragActive (2nd finger begins and we are in doubleTapDragArmed)
///
/// twoFingerEvaluating    (waiting for dominant axis lock)
///   → twoFingerScroll    (centroid move dominant: |Δc| > 1.5 × |Δspread|)
///   → twoFingerZoom      (spread dominant)
///   → idle               (all fingers ended without lock → right-click tap or nothing)
///
/// twoFingerScroll        (locked: centroid translation → STYLUS_SCROLL)
///   → idle               (all fingers ended)
///
/// twoFingerZoom          (locked: spread change → STYLUS_ZOOM)
///   → idle               (all fingers ended)
///
/// doubleTapDragArmed     (first tap completed within 350 ms + 20 pt, waiting for second down)
///   → doubleTapDragActive (second finger begins within window)
///   → idle               (window expired — detected by CADisplayLink poke from canvas)
///
/// doubleTapDragActive    (holding LEFT_DOWN; drag emits CURSOR_DELTA)
///   → idle               (finger ended or cancelled → emit LEFT_UP)
/// ```
///
/// # Timing / spatial constants
/// All constants are per spec.md (DOUBLE_TAP_DRAG_WINDOW_MS=350, DOUBLE_TAP_DRAG_SPATIAL_TOLERANCE_PT=20,
/// PINCH_THRESHOLD_PT=10, tapMaxSlop=10pt, tapMaxDuration=250ms).
public struct TouchRouter {

    // MARK: – Constants

    /// Maximum duration (seconds) for a touch to qualify as a tap.
    private static let tapMaxDuration: TimeInterval = 0.250

    /// Grace period (seconds) after a scroll-end (phase=2) during which a tap is
    /// interpreted as "stop momentum" and suppressed rather than firing a click.
    /// Mirrors Magic Trackpad behaviour: tap-to-stop-inertia within ~500 ms of lift-off
    /// does not open a context menu or trigger a primary click.
    private static let momentumCancelGraceS: TimeInterval = 0.5

    /// Maximum movement (points) from touch-down position for a tap to be valid.
    /// Boundary inclusive: ≤ 10 pt is a tap.
    private static let tapMaxSlop: CGFloat = 10

    /// Maximum inter-tap gap (seconds) for double-tap-drag recognition.
    /// Boundary inclusive: ≤ 350 ms qualifies.
    private static let doubleTapWindow: TimeInterval = 0.350

    /// Maximum distance (points) between first and second tap locations for double-tap-drag.
    /// Boundary inclusive: ≤ 20 pt qualifies.
    private static let doubleTapSpatialTolerance: CGFloat = 20

    /// Minimum spread change (points) required to classify a two-finger gesture as zoom.
    /// Option A (Block M Round 5): an absolute spread-first heuristic. If |Δspread| >= this
    /// threshold we lock to zoom before testing centroid motion — prevents centroid drift
    /// during real pinches from falsely winning the scroll classification.
    ///
    /// Per spec.md PINCH_THRESHOLD_PT = 10.
    private static let pinchThresholdPt: CGFloat = 10

    // MARK: – Injected clock

    /// Injected monotonic clock. The canvas layer passes `{ CACurrentMediaTime() }`.
    /// Tests pass a fake closure. NEVER call any real clock inside this struct.
    private let now: () -> TimeInterval

    // MARK: – State

    private var state: State = .idle

    // MARK: – Per-finger tracking

    /// Active fingers: id → (downLocation, downTimestamp, currentLocation).
    private var fingers: [UUID: FingerInfo] = [:]

    private struct FingerInfo {
        var downLocation: CGPoint
        var downTimestamp: TimeInterval
        var currentLocation: CGPoint
        /// True once this finger has moved more than `tapMaxSlop` from its down position.
        var dragDisqualified: Bool = false
    }

    // MARK: – Two-finger tracking state

    private var prevCentroid: CGPoint? = nil
    private var prevSpread: CGFloat = 0
    private var twoFingerTapDisqualified: Bool = false
    private var twoFingerDownTime: TimeInterval = 0

    /// Centroid at the moment two fingers went down — used for cumulative centroid-change
    /// comparison during `twoFingerEvaluating`. Reset by `resetTwoFingerState`.
    private var initialCentroid: CGPoint = .zero

    /// Spread at the moment two fingers went down — used for cumulative spread-change
    /// comparison during `twoFingerEvaluating`. Reset by `resetTwoFingerState`.
    private var initialSpread: CGFloat = 0

    // MARK: – Lock mode for scroll/zoom hysteresis

    private enum LockMode: Equatable { case none, scroll, zoom }
    private var lockMode: LockMode = .none

    // MARK: – Gesture phase tracking

    /// True once a SCROLL_BEGIN frame (phase=0) has been emitted for the current
    /// scroll gesture. Uses a state field (not sample count) per hard rule: the
    /// phase progression must not infer "is this the first emit" from any metric
    /// other than an explicit flag. Resets in `resetTwoFingerState`.
    private var scrollEmittedBegin: Bool = false

    /// Same as `scrollEmittedBegin` but for zoom gestures.
    private var zoomEmittedBegin: Bool = false

    /// Last scroll delta emitted during `twoFingerScroll` state.
    /// Carried into the phase=2 (ended) frame so the Mac's `startMomentumDecay`
    /// sees non-zero lift-off velocity and starts inertia. Without this, the END
    /// frame always carries (0, 0) → momentum threshold check fails → no inertia.
    /// Resets in `resetTwoFingerState`.
    private var lastScrollDeltaX: Float = 0
    private var lastScrollDeltaY: Float = 0

    /// Sliding window of the last N per-frame scroll deltas.
    /// Used to compute a velocity average for the END frame so single-finger-first
    /// lift (which contaminates the final instantaneous delta with near-zero values)
    /// does not suppress momentum. Max 5 entries; oldest entry is dropped on overflow.
    /// Resets at the start of every new scroll gesture via `resetTwoFingerState`.
    private var recentScrollDeltas: [(dx: Float, dy: Float)] = []
    private static let recentScrollWindowSize = 5

    // MARK: – Double-tap-drag bookkeeping

    /// Location of the first tap (used for spatial tolerance check on second tap).
    private var firstTapLocation: CGPoint? = nil

    /// Timestamp when the first tap's finger lifted (used for timing window check).
    private var firstTapUpTime: TimeInterval? = nil

    // MARK: – Momentum-cancel grace period

    /// Timestamp of the last scroll-end (phase=2) emission. Used to suppress tap clicks
    /// that fall within `momentumCancelGraceS` of a scroll-end, matching Magic Trackpad
    /// behaviour where a tap-to-stop-momentum does not also fire a click.
    /// Reset to 0 at init; never reset by `resetTwoFingerState` (it must survive into
    /// the idle state after the scroll session ends).
    private var lastScrollEndAt: TimeInterval = 0

    // MARK: – Init

    public init(now: @escaping () -> TimeInterval) {
        self.now = now
    }

    // MARK: – State enum

    private enum State: Equatable {
        case idle
        case oneFingerActive
        case twoFingerEvaluating
        case twoFingerScroll
        case twoFingerZoom
        case doubleTapDragArmed
        case doubleTapDragActive
    }

    // MARK: – Public API

    /// Process one touch sample and return the events to send to the server.
    ///
    /// - Parameters:
    ///   - sample: The touch sample from the canvas.
    ///   - phase: The touch phase (began/moved/ended/cancelled).
    /// - Returns: Zero or more `StylusEvent` values. May be empty for intermediate moves.
    @discardableResult
    public mutating func process(_ sample: TouchSample, phase: TouchPhase) -> [StylusEvent] {
        switch phase {
        case .began:   return handleBegan(sample)
        case .moved:   return handleMoved(sample)
        case .ended:   return handleEnded(sample)
        case .cancelled: return handleCancelled(sample)
        }
    }

    /// Process a batch of touch samples for a single UIKit touch callback and return
    /// the resulting events atomically.
    ///
    /// This is the PREFERRED API for `CaptureViewModel.ingest`. When iOS delivers multiple
    /// simultaneous finger updates in one `touchesMoved` callback, calling the single-sample
    /// `process` API in a loop emits one scroll/zoom event per finger, doubling the event rate
    /// and causing choppy scroll on the Mac (Bug 2 fix).
    ///
    /// For 2-finger scroll/zoom in steady state, this method emits AT MOST ONE scroll or
    /// zoom event per call, computed from the final centroid/spread after all samples are
    /// applied — regardless of how many samples are in the batch.
    ///
    /// For `began` and `ended` phases each sample is processed individually because each
    /// finger transition is an independent state-machine event.
    ///
    /// - Parameters:
    ///   - samples: All touch samples from one UIKit `touchesBegan/Moved/Ended/Cancelled` call.
    ///   - phase: The touch phase shared by all samples in this batch.
    /// - Returns: Zero or more `StylusEvent` values.
    @discardableResult
    public mutating func process(samples: [TouchSample], phase: TouchPhase) -> [StylusEvent] {
        guard !samples.isEmpty else { return [] }

        switch phase {
        case .began, .ended, .cancelled:
            // Each finger transition is a separate state event — process individually
            // and concatenate. State transitions (tap, right-click, scroll-end) must fire
            // once per finger, not be coalesced.
            return samples.flatMap { process($0, phase: phase) }

        case .moved:
            // Bug 2 fix: update ALL finger states first, then emit ONE event.
            // If we were to call process(_:phase:) per sample, each call would compute
            // a partial centroid (only some fingers updated) and emit a separate event.
            // Instead: update the internal finger positions for every sample, then call
            // handleTwoFingerFrameEmit once to produce at most one scroll/zoom event.
            //
            // For 1-finger moves the loop still runs once, so single-sample behaviour
            // is preserved exactly.
            if samples.count == 1 {
                return process(samples[0], phase: .moved)
            }
            // Multi-sample moved: update state for each sample without emitting,
            // then emit a single coalesced event.
            return handleBatchMoved(samples: samples)
        }
    }

    // MARK: – Batch moved (Bug 2)

    /// Updates finger positions for all samples in `samples` and then emits at most one
    /// scroll/zoom event computed from the final two-finger centroid/spread.
    ///
    /// Single-finger (or non-2-finger) cases fall back to sequential processing.
    private mutating func handleBatchMoved(samples: [TouchSample]) -> [StylusEvent] {
        // Determine if we are in a 2-finger state before updating.
        let isInTwoFingerState = state == .twoFingerEvaluating
            || state == .twoFingerScroll
            || state == .twoFingerZoom

        if !isInTwoFingerState {
            // Not a 2-finger state — process sequentially (safe, no coalescing needed).
            return samples.flatMap { process($0, phase: .moved) }
        }

        // 2-finger state: apply all position updates, accumulate tap-disqualification,
        // then emit once.
        for sample in samples {
            guard var info = fingers[sample.id] else { continue }
            info.currentLocation = sample.location
            let totalMovement = GestureGeometry.distance(info.downLocation, info.currentLocation)
            if totalMovement > Self.tapMaxSlop {
                info.dragDisqualified = true
                twoFingerTapDisqualified = true
            }
            fingers[sample.id] = info
        }

        // Use the last sample's timestamp for the event (most recent).
        let representativeSample = samples.last!
        return handleTwoFingerMove(sample: representativeSample)
    }

    // MARK: – Began

    private mutating func handleBegan(_ sample: TouchSample) -> [StylusEvent] {
        fingers[sample.id] = FingerInfo(
            downLocation: sample.location,
            downTimestamp: sample.timestamp,
            currentLocation: sample.location
        )

        switch state {
        case .idle:
            // Check for double-tap-drag: is there an armed first tap waiting?
            if let armedTime = firstTapUpTime,
               let armedLoc = firstTapLocation {
                let gap = sample.timestamp - armedTime
                let dist = GestureGeometry.distance(sample.location, armedLoc)

                if gap <= Self.doubleTapWindow && dist <= Self.doubleTapSpatialTolerance {
                    // Enters doubleTapDragActive — emit LEFT_DOWN immediately.
                    // buttons=0x08 = BUTTON_PRIMARY (wire-format bit 3, per protocol §Flags).
                    state = .doubleTapDragActive
                    firstTapUpTime = nil
                    firstTapLocation = nil
                    return [.stylusButton(buttons: 0x08, primaryDown: true)]
                }
            }
            // No armed tap — normal 1-finger active.
            // Momentum-cancel hint: emit a zero-delta scroll-begin immediately so the Mac
            // cancels any in-flight scroll momentum on the FIRST finger touch, not just
            // when a second finger joins. Mirrors Magic Trackpad behaviour where any
            // contact — even a single finger — stops momentum instantly.
            //
            // scrollEmittedBegin is set to true so that if a second finger joins later,
            // the oneFingerActive → twoFingerEvaluating branch knows the begin was
            // already sent and suppresses a duplicate emit (keeping ONE begin per session).
            //
            // Side effects (harmless):
            // - 1-finger tap: scroll-begin(0,0) is sent before the LEFT_DOWN/LEFT_UP.
            //   Zero-delta scroll is visually inert on the Mac.
            // - 1-finger drag: scroll-begin(0,0) precedes the cursorDelta stream.
            //   The Mac's scroll state machine receives an orphaned begin with no matching
            //   end; this is the same pattern as the existing 2-finger tap path and is safe.
            // - We do NOT emit phase=2 (end) when a 1-finger gesture completes — the
            //   begin emitted here is intentionally orphaned when the gesture is not a
            //   scroll/zoom. Phase=2 is only sent at the end of a real twoFingerScroll session.
            state = .oneFingerActive
            scrollEmittedBegin = true
            return [.stylusScroll(deltaX: 0, deltaY: 0, phase: 0)]

        case .oneFingerActive:
            // Second finger joins — transition to 2-finger evaluation.
            // Capture whether the first-finger touchdown already sent a scroll-begin.
            // resetTwoFingerState clears scrollEmittedBegin, so we must read it before
            // calling reset and restore it afterwards to avoid a duplicate phase=0 emit.
            let beginAlreadySent = scrollEmittedBegin
            state = .twoFingerEvaluating
            resetTwoFingerState(at: sample.timestamp)
            // Seed prevCentroid/prevSpread from BOTH fingers' current positions so
            // the FIRST handleTwoFingerMove call computes a delta relative to the
            // actual two-finger down position. Without this, prevCentroid is nil on
            // the first moved event and gets lazily set to the half-updated centroid
            // (only one finger has moved), producing a large spurious first delta.
            // iOS delivers finger 1 and finger 2 as separate .began callbacks; by the
            // time we reach this branch, both fingers are already in `fingers`, so
            // using fingers.values gives the correct two-finger centroid at down time.
            let downLocs = fingers.values.map { $0.currentLocation }
            let downCentroid = GestureGeometry.centroid(downLocs)
            let downSpread   = GestureGeometry.spread(downLocs)
            prevCentroid    = downCentroid
            prevSpread      = downSpread
            // Bug 1 fix: store the INITIAL two-finger position for cumulative tracking.
            // The lock decision compares against these anchors, not against the previous
            // frame, so slow pinches accumulate properly across many small per-frame deltas.
            initialCentroid = downCentroid
            initialSpread   = downSpread
            print("[TouchRouter] entering twoFingerEvaluating: initialCentroid=\(initialCentroid) initialSpread=\(initialSpread)")
            // Momentum-cancel: if the first-finger touchdown already emitted a scroll-begin
            // (Part A), we must NOT emit another one here — that would send two phase=0
            // events in a row, which is malformed. Restore the flag and return no scroll event.
            // If somehow scrollEmittedBegin was false (defensive: shouldn't happen with Part A),
            // fall back to the original Round 8 behaviour and emit now.
            if beginAlreadySent {
                scrollEmittedBegin = true
                return []
            }
            // Fallback (defensive): first finger did not emit — emit scroll-begin now.
            // (This path should not be reached with Part A active, but is safe.)
            scrollEmittedBegin = true
            return [.stylusScroll(deltaX: 0, deltaY: 0, phase: 0)]

        case .doubleTapDragArmed:
            // Second tap begins — check timing + spatial.
            if let armedTime = firstTapUpTime,
               let armedLoc = firstTapLocation {
                let gap = sample.timestamp - armedTime
                let dist = GestureGeometry.distance(sample.location, armedLoc)

                if gap <= Self.doubleTapWindow && dist <= Self.doubleTapSpatialTolerance {
                    // buttons=0x08 = BUTTON_PRIMARY (wire-format bit 3, per protocol §Flags).
                    state = .doubleTapDragActive
                    firstTapUpTime = nil
                    firstTapLocation = nil
                    return [.stylusButton(buttons: 0x08, primaryDown: true)]
                }
            }
            // Outside window/spatial — treat as new tap.
            // Emit scroll-begin (Part A) to cancel any Mac momentum, same as idle → oneFingerActive.
            state = .oneFingerActive
            firstTapUpTime = nil
            firstTapLocation = nil
            scrollEmittedBegin = true
            return [.stylusScroll(deltaX: 0, deltaY: 0, phase: 0)]

        case .twoFingerEvaluating, .twoFingerScroll, .twoFingerZoom:
            // 3+ fingers: ignore additional contacts.
            return []

        case .doubleTapDragActive:
            // Additional finger while holding drag — ignore.
            return []
        }
    }

    // MARK: – Moved

    private mutating func handleMoved(_ sample: TouchSample) -> [StylusEvent] {
        guard var info = fingers[sample.id] else { return [] }

        let prevLocation = info.currentLocation
        info.currentLocation = sample.location

        // Check slop disqualification for tap purposes.
        let totalMovement = GestureGeometry.distance(info.downLocation, info.currentLocation)
        if totalMovement > Self.tapMaxSlop {
            info.dragDisqualified = true
        }

        // Propagate cumulative 2-finger tap disqualification.
        if state == .twoFingerEvaluating || state == .twoFingerScroll || state == .twoFingerZoom {
            if info.dragDisqualified { twoFingerTapDisqualified = true }
        }

        fingers[sample.id] = info

        switch state {
        case .oneFingerActive:
            guard info.dragDisqualified else { return [] }
            // First significant move — start emitting deltas.
            let dx = clamp16(sample.location.x - prevLocation.x)
            let dy = clamp16(sample.location.y - prevLocation.y)
            return [.cursorDelta(dx: dx, dy: dy)]

        case .doubleTapDragActive:
            // Holding LEFT — emit cursor deltas for every move.
            let dx = clamp16(sample.location.x - prevLocation.x)
            let dy = clamp16(sample.location.y - prevLocation.y)
            return [.cursorDelta(dx: dx, dy: dy)]

        case .twoFingerEvaluating, .twoFingerScroll, .twoFingerZoom:
            return handleTwoFingerMove(sample: sample)

        case .idle, .doubleTapDragArmed:
            return []
        }
    }

    // MARK: – Ended

    private mutating func handleEnded(_ sample: TouchSample) -> [StylusEvent] {
        guard let info = fingers.removeValue(forKey: sample.id) else { return [] }

        switch state {
        case .oneFingerActive:
            let events = evaluateTap(info: info, endTimestamp: sample.timestamp)
            if !events.isEmpty {
                // This was a valid tap — arm double-tap-drag window.
                firstTapLocation = info.downLocation
                firstTapUpTime = sample.timestamp
                state = .doubleTapDragArmed
            } else {
                firstTapUpTime = nil
                firstTapLocation = nil
                state = .idle
            }
            return events

        case .doubleTapDragActive:
            if fingers.isEmpty {
                // Finger lifted — release the held LEFT button.
                // buttons=0x00: both BUTTON_PRIMARY (bit 3) and BUTTON_SECONDARY (bit 4) clear.
                state = .idle
                firstTapUpTime = nil
                firstTapLocation = nil
                return [.stylusButton(buttons: 0x00, primaryDown: false)]
            }
            return []

        case .twoFingerEvaluating, .twoFingerScroll, .twoFingerZoom:
            return handleTwoFingerEnd(sample: sample, info: info)

        case .idle:
            return []

        case .doubleTapDragArmed:
            // Finger ended while armed — shouldn't happen with proper canvas logic, but handle cleanly.
            return []
        }
    }

    // MARK: – Cancelled

    private mutating func handleCancelled(_ sample: TouchSample) -> [StylusEvent] {
        fingers.removeValue(forKey: sample.id)

        switch state {
        case .doubleTapDragActive:
            if fingers.isEmpty {
                state = .idle
                firstTapUpTime = nil
                firstTapLocation = nil
                // MUST emit LEFT_UP to release the held button.
                return [.stylusButton(buttons: 0x00, primaryDown: false)]
            }
            return []

        case .oneFingerActive, .twoFingerEvaluating, .twoFingerScroll, .twoFingerZoom:
            if fingers.isEmpty {
                state = .idle
                firstTapUpTime = nil
                firstTapLocation = nil
            }
            return []

        case .doubleTapDragArmed, .idle:
            state = .idle
            firstTapUpTime = nil
            firstTapLocation = nil
            return []
        }
    }

    // MARK: – Tap evaluation

    /// Returns `[LEFT_DOWN, LEFT_UP]` if the touch qualifies as a tap; empty otherwise.
    ///
    /// Wire-format button values (per protocol §Flags and §STYLUS_BUTTON):
    ///   0x08 = BUTTON_PRIMARY pressed  (bit 3 of flags / buttons field)
    ///   0x00 = all buttons released
    ///
    /// Momentum-cancel grace: if this tap falls within `momentumCancelGraceS` of the
    /// last scroll-end (phase=2) emission, the tap is suppressed. The user's intent is
    /// "stop the momentum scroll", not "click". This matches Magic Trackpad behaviour.
    private func evaluateTap(info: FingerInfo, endTimestamp: TimeInterval) -> [StylusEvent] {
        let duration = endTimestamp - info.downTimestamp
        guard duration <= Self.tapMaxDuration && !info.dragDisqualified else {
            return []
        }
        // Grace-period suppression: tap fired within 500 ms of a scroll-end is treated
        // as a momentum-cancel gesture, not a click.
        let sinceScrollEnd = endTimestamp - lastScrollEndAt
        if lastScrollEndAt > 0 && sinceScrollEnd < Self.momentumCancelGraceS {
            print("[TouchRouter] 1-finger tap suppressed (momentum-cancel grace: \(sinceScrollEnd)s since scroll-end)")
            return []
        }
        return [
            .stylusButton(buttons: 0x08, primaryDown: true),
            .stylusButton(buttons: 0x00, primaryDown: false)
        ]
    }

    // MARK: – Two-finger move handling

    private mutating func handleTwoFingerMove(sample: TouchSample) -> [StylusEvent] {
        let locs = fingers.values.map { $0.currentLocation }
        guard locs.count >= 2 else { return [] }

        let currentCentroid = GestureGeometry.centroid(locs)
        let currentSpread   = GestureGeometry.spread(locs)

        guard let prev = prevCentroid else {
            prevCentroid = currentCentroid
            prevSpread   = currentSpread
            return []
        }

        let deltaX = currentCentroid.x - prev.x
        let deltaY = currentCentroid.y - prev.y

        // Capture old spread BEFORE updating state — needed for correct magnification ratio.
        let oldSpread = prevSpread

        prevCentroid = currentCentroid
        prevSpread   = currentSpread

        switch state {
        case .twoFingerEvaluating:
            // Lock classification — cumulative absolute-threshold, spread-first (Bug 1 fix):
            //   1. If |currentSpread - initialSpread| >= PINCH_THRESHOLD_PT → zoom wins.
            //   2. Else if distance(currentCentroid, initialCentroid) >= 10 pt → scroll wins.
            //   3. Else: stay evaluating (no lock yet).
            //
            // CRITICAL: both thresholds are measured from the INITIAL two-finger-down
            // position, NOT from the previous frame. Per-frame deltas for slow gestures
            // are 1–3 pt, which never reaches 10 pt in a single frame. Cumulative tracking
            // accumulates these small per-frame deltas so slow pinches are recognised.
            if lockMode == .none {
                let cumulativeSpreadChange = abs(currentSpread - initialSpread)
                let cumulativeCentroidChange = GestureGeometry.distance(currentCentroid, initialCentroid)
                print("[TouchRouter] evaluating: spreadDelta=\(cumulativeSpreadChange) centroidDelta=\(cumulativeCentroidChange) thresholdSpread=\(Self.pinchThresholdPt) thresholdCentroid=10")
                if cumulativeSpreadChange >= Self.pinchThresholdPt {
                    lockMode = .zoom
                    state = .twoFingerZoom
                    print("[TouchRouter] LOCKED to twoFingerZoom (spreadDelta=\(cumulativeSpreadChange) centroidDelta=\(cumulativeCentroidChange))")
                } else if cumulativeCentroidChange >= Self.tapMaxSlop {
                    lockMode = .scroll
                    state = .twoFingerScroll
                    print("[TouchRouter] LOCKED to twoFingerScroll (spreadDelta=\(cumulativeSpreadChange) centroidDelta=\(cumulativeCentroidChange))")
                }
            }
            // Only emit after lock is established; suppress pre-lock frames entirely.
            return emitTwoFingerEvent(
                deltaX: deltaX, deltaY: deltaY,
                currentSpread: currentSpread, oldSpread: oldSpread
            )

        case .twoFingerScroll:
            // Hysteresis: stay in scroll even if spread now dominates.
            // Emit phase=0 (begin) on the FIRST frame after lock, phase=1 (changed) thereafter.
            // Phase is tracked by `scrollEmittedBegin` — NOT by sample count.
            let scrollPhase: UInt8
            if !scrollEmittedBegin {
                scrollEmittedBegin = true
                scrollPhase = 0 // begin
            } else {
                scrollPhase = 1 // changed
            }
            // Track last delta for momentum: the END frame (phase=2) must carry the
            // lift-off velocity so Mac's startMomentumDecay sees non-zero input.
            lastScrollDeltaX = Float(deltaX)
            lastScrollDeltaY = Float(deltaY)
            // Sliding-window velocity accumulation for momentum END frame.
            // Keeps the last N frames so the average is available when fingers lift.
            recentScrollDeltas.append((dx: Float(deltaX), dy: Float(deltaY)))
            if recentScrollDeltas.count > Self.recentScrollWindowSize {
                recentScrollDeltas.removeFirst()
            }
            return [.stylusScroll(deltaX: Float(deltaX), deltaY: Float(deltaY), phase: scrollPhase)]

        case .twoFingerZoom:
            // Use oldSpread (before update) so magnification = currentSpread / previousSpread.
            guard oldSpread > 0 else { return [] }
            let magnification = Float(currentSpread / oldSpread)
            // Emit phase=0 (begin) on the FIRST zoom frame, phase=1 (changed) thereafter.
            // Phase is tracked by `zoomEmittedBegin` — NOT by sample count.
            let zoomPhase: UInt8
            if !zoomEmittedBegin {
                zoomEmittedBegin = true
                zoomPhase = 0 // begin
            } else {
                zoomPhase = 1 // changed
            }
            return [.stylusZoom(magnification: magnification, phase: zoomPhase)]

        default:
            return []
        }
    }

    private mutating func emitTwoFingerEvent(
        deltaX: CGFloat,
        deltaY: CGFloat,
        currentSpread: CGFloat,
        oldSpread: CGFloat
    ) -> [StylusEvent] {
        switch lockMode {
        case .scroll:
            // Lock was just established on this frame.
            // If scrollEmittedBegin is already true (momentum-cancel zero-delta was sent
            // on two-finger down), this frame is phase=1 (changed). Otherwise it is
            // phase=0 (begin). Either way, mark begin as emitted so subsequent frames
            // in `.twoFingerScroll` emit phase=1.
            let scrollPhase: UInt8 = scrollEmittedBegin ? 1 : 0
            scrollEmittedBegin = true
            // Track for momentum on END frame.
            lastScrollDeltaX = Float(deltaX)
            lastScrollDeltaY = Float(deltaY)
            // Begin the sliding-window accumulation from the first emitted frame.
            recentScrollDeltas.append((dx: Float(deltaX), dy: Float(deltaY)))
            if recentScrollDeltas.count > Self.recentScrollWindowSize {
                recentScrollDeltas.removeFirst()
            }
            return [.stylusScroll(deltaX: Float(deltaX), deltaY: Float(deltaY), phase: scrollPhase)]
        case .zoom:
            // Lock was just established on this frame — always the begin frame for zoom.
            // (The momentum-cancel zero-delta sent on two-finger down was a scroll-begin,
            // not a zoom-begin, so zoomEmittedBegin is still false here.)
            zoomEmittedBegin = true
            let mag = oldSpread > 0 ? Float(currentSpread / oldSpread) : 1
            return [.stylusZoom(magnification: mag, phase: 0)]
        case .none:
            // No lock yet — suppress until we know scroll vs zoom.
            return []
        }
    }

    // MARK: – Two-finger end handling

    private mutating func handleTwoFingerEnd(
        sample: TouchSample,
        info: FingerInfo
    ) -> [StylusEvent] {
        if fingers.isEmpty {
            // All fingers lifted — check for right-click tap or emit phase=2 terminator.
            let elapsed = sample.timestamp - twoFingerDownTime
            let wasQuickEnough = elapsed <= Self.tapMaxDuration
            let wasSmallEnough = !twoFingerTapDisqualified
            let capturedLock = lockMode

            defer {
                state = .idle
                resetTwoFingerState(at: 0)
                lockMode = .none
            }

            print("[TouchRouter] twoFingerEnd: lockMode=\(capturedLock) lastScrollDelta=(\(lastScrollDeltaX), \(lastScrollDeltaY))")

            if wasQuickEnough && wasSmallEnough && capturedLock == .none {
                // Grace-period suppression: 2-finger tap within 500 ms of a scroll-end is
                // a momentum-cancel gesture, not a right-click. Mirrors Magic Trackpad UX
                // where tap-to-stop-inertia never opens the context menu.
                let sinceScrollEnd = sample.timestamp - lastScrollEndAt
                if lastScrollEndAt > 0 && sinceScrollEnd < Self.momentumCancelGraceS {
                    print("[TouchRouter] 2-finger TAP suppressed (momentum-cancel grace: \(sinceScrollEnd)s since scroll-end)")
                    return []
                }
                // 2-finger tap → right-click.
                // buttons=0x10 = BUTTON_SECONDARY (bit 4 of flags/buttons per wire protocol §Flags).
                // buttons=0x00 = all buttons released.
                print("[TouchRouter] 2-finger TAP detected, emitting RIGHT_DOWN+RIGHT_UP")
                return [
                    .stylusButton(buttons: 0x10, primaryDown: false),
                    .stylusButton(buttons: 0x00, primaryDown: false)
                ]
            }

            // Gesture was a scroll or zoom — emit phase=2 (ended) to let the Mac commit.
            // IMPORTANT: carry the last observed velocity in the END frame.
            // Mac's CGEventInjector.startMomentumDecay only fires when
            // abs(initialDeltaX) + abs(initialDeltaY) >= 10. Emitting (0,0) here
            // would always fail that threshold → no inertia after scroll lift-off.
            //
            // Velocity-window averaging: when the user lifts one finger first, the
            // remaining single-finger centroid decelerates, contaminating the last
            // instantaneous delta with a near-zero value. Using the average of the last
            // N frames produces a lift-off velocity that crosses the momentum threshold
            // even under natural single-finger-first lift behaviour.
            if capturedLock == .scroll {
                let recentSum = recentScrollDeltas.reduce(into: (dx: Float(0), dy: Float(0))) {
                    $0.dx += $1.dx; $0.dy += $1.dy
                }
                let count = max(1, recentScrollDeltas.count)
                let endDeltaX = recentSum.dx / Float(count)
                let endDeltaY = recentSum.dy / Float(count)
                print("[TouchRouter] emitting scroll END phase=2 deltaX=\(endDeltaX) deltaY=\(endDeltaY) (avg over \(count) frames, last=\(lastScrollDeltaX),\(lastScrollDeltaY))")
                // Record the scroll-end timestamp so the momentum-cancel grace period
                // check in tap evaluation knows a scroll just ended.
                lastScrollEndAt = sample.timestamp
                return [.stylusScroll(deltaX: endDeltaX, deltaY: endDeltaY, phase: 2)]
            }
            if capturedLock == .zoom {
                print("[TouchRouter] emitting zoom END phase=2 magnification=1.0")
                return [.stylusZoom(magnification: 1.0, phase: 2)]
            }
        }
        return []
    }

    // MARK: – Helpers

    private mutating func resetTwoFingerState(at timestamp: TimeInterval) {
        prevCentroid = nil
        prevSpread = 0
        initialCentroid = .zero
        initialSpread = 0
        twoFingerTapDisqualified = false
        twoFingerDownTime = timestamp
        lockMode = .none
        scrollEmittedBegin = false
        zoomEmittedBegin = false
        lastScrollDeltaX = 0
        lastScrollDeltaY = 0
        recentScrollDeltas.removeAll()
    }

    /// Clamp a CGFloat delta to Int16 range.
    private func clamp16(_ value: CGFloat) -> Int16 {
        let clamped = max(CGFloat(Int16.min), min(CGFloat(Int16.max), value))
        return Int16(clamped)
    }
}
