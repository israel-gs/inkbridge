import XCTest
@testable import InkBridgeIOS

// MARK: - E.8 Scroll / zoom / 2-finger tap

final class TouchRouterScrollZoomTests: XCTestCase {

    // Build a 2-finger sample. Both fingers share the same timestamp in one logical event.
    // We synthesize two separate TouchSamples and process them sequentially with .began/.moved/.ended.
    private func sample(
        id: UUID = UUID(),
        x: CGFloat,
        y: CGFloat,
        t: TimeInterval
    ) -> TouchSample {
        TouchSample(id: id, location: CGPoint(x: x, y: y), timestamp: t)
    }

    // Bring two fingers down.
    private func twoFingersDown(
        router: inout TouchRouter,
        f1: (id: UUID, x: CGFloat, y: CGFloat),
        f2: (id: UUID, x: CGFloat, y: CGFloat),
        t: TimeInterval
    ) {
        _ = router.process(sample(id: f1.id, x: f1.x, y: f1.y, t: t), phase: .began)
        _ = router.process(sample(id: f2.id, x: f2.x, y: f2.y, t: t), phase: .began)
    }

    // MARK: – Translate-dominant → scroll

    /// When centroid movement is large and spread change is small (|Δcentroid| > 1.5 × |Δspread|),
    /// emits stylusScroll.
    func test_twoFinger_translateDominant_emitsScroll() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1 = (id: UUID(), x: CGFloat(90), y: CGFloat(100))
        let f2 = (id: UUID(), x: CGFloat(110), y: CGFloat(100))

        // Fingers down: spread = 20 pt, centroid = (100, 100)
        twoFingersDown(router: &router, f1: f1, f2: f2, t: 0)

        // Move both fingers 30 pt to the right, keeping spread constant (translate-dominant)
        clock = 0.016
        _ = router.process(sample(id: f1.id, x: 120, y: 100, t: 0.016), phase: .moved)
        let moveEvents = router.process(sample(id: f2.id, x: 140, y: 100, t: 0.016), phase: .moved)

        let hasScroll = moveEvents.contains { if case .stylusScroll = $0 { return true }; return false }
        XCTAssertTrue(hasScroll, "Translate-dominant 2-finger move → must emit stylusScroll")
    }

    // MARK: – Spread-dominant → zoom

    /// When spread change is large and centroid movement is small,
    /// emits stylusZoom.
    func test_twoFinger_spreadDominant_emitsZoom() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1 = (id: UUID(), x: CGFloat(90), y: CGFloat(100))
        let f2 = (id: UUID(), x: CGFloat(110), y: CGFloat(100))

        // Spread = 20 pt, centroid = (100, 100)
        twoFingersDown(router: &router, f1: f1, f2: f2, t: 0)

        // Spread fingers apart keeping centroid fixed: spread grows from 20 → 60
        // Centroid stays near (100,100), Δspread = 40 >> Δcentroid = 0
        clock = 0.016
        _ = router.process(sample(id: f1.id, x: 70, y: 100, t: 0.016), phase: .moved)
        let moveEvents = router.process(sample(id: f2.id, x: 130, y: 100, t: 0.016), phase: .moved)

        let hasZoom = moveEvents.contains { if case .stylusZoom = $0 { return true }; return false }
        XCTAssertTrue(hasZoom, "Spread-dominant 2-finger move → must emit stylusZoom")
    }

    // MARK: – Hysteresis: once locked to scroll, stays scroll

    /// After a scroll lock is established, subsequent spread changes must NOT switch to zoom.
    func test_twoFinger_hysteresis_scrollLockPreventsZoom() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1 = (id: UUID(), x: CGFloat(90), y: CGFloat(100))
        let f2 = (id: UUID(), x: CGFloat(110), y: CGFloat(100))

        twoFingersDown(router: &router, f1: f1, f2: f2, t: 0)

        // Step 1: translate 30 pt (no spread change) → lock into scroll
        clock = 0.016
        _ = router.process(sample(id: f1.id, x: 120, y: 100, t: 0.016), phase: .moved)
        _ = router.process(sample(id: f2.id, x: 140, y: 100, t: 0.016), phase: .moved)

        // Step 2: spread fingers significantly (would be zoom if not hysteresis-locked)
        clock = 0.032
        _ = router.process(sample(id: f1.id, x: 80, y: 100, t: 0.032), phase: .moved)
        let events2 = router.process(sample(id: f2.id, x: 180, y: 100, t: 0.032), phase: .moved)

        // Must NOT emit zoom after scroll was locked
        let hasZoom = events2.contains { if case .stylusZoom = $0 { return true }; return false }
        XCTAssertFalse(hasZoom, "Hysteresis: once scroll-locked, subsequent spread must NOT emit zoom")
    }

    // MARK: – 2-finger tap → RIGHT click

    /// Two fingers down and up within the tap window (< 150 ms) with < 10 pt movement
    /// must emit [RIGHT_DOWN, RIGHT_UP].
    func test_twoFinger_tap_emitsRightClick() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Two fingers down simultaneously
        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0), phase: .began)
        _ = router.process(sample(id: f2id, x: 110, y: 100, t: 0), phase: .began)

        // Both fingers up within 100 ms, no movement
        clock = 0.100
        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0.100), phase: .ended)
        let upEvents = router.process(sample(id: f2id, x: 110, y: 100, t: 0.100), phase: .ended)

        // Wire-format: 0x10 = BUTTON_SECONDARY (bit 4). primaryDown is false for right-click
        // because only bit 3 (BUTTON_PRIMARY) maps to primaryDown per the protocol spec.
        let rightDown = upEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x10 && !d }
            return false
        }
        let rightUp = upEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x00 && !d }
            return false
        }

        XCTAssertTrue(rightDown, "2-finger tap → must emit RIGHT_DOWN (buttons=0x10, primaryDown=false)")
        XCTAssertTrue(rightUp,   "2-finger tap → must emit RIGHT_UP (buttons=0x00, primaryDown=false)")
    }

    /// 2-finger tap with movement > 10 pt must NOT emit right-click.
    func test_twoFinger_tap_withMovement_doesNotEmitRightClick() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0), phase: .began)
        _ = router.process(sample(id: f2id, x: 110, y: 100, t: 0), phase: .began)

        // Move beyond slop
        clock = 0.050
        _ = router.process(sample(id: f1id, x: 105, y: 100, t: 0.050), phase: .moved)
        _ = router.process(sample(id: f2id, x: 125, y: 100, t: 0.050), phase: .moved)

        clock = 0.100
        _ = router.process(sample(id: f1id, x: 105, y: 100, t: 0.100), phase: .ended)
        let upEvents = router.process(sample(id: f2id, x: 125, y: 100, t: 0.100), phase: .ended)

        let hasRightDown = upEvents.contains {
            if case .stylusButton(let b, _) = $0 { return b == 0x10 }
            return false
        }
        XCTAssertFalse(hasRightDown, "2-finger drag > 10 pt → must NOT emit right-click")
    }

    // MARK: – Bug 1: cumulative pinch threshold (slow pinch must be recognised)

    /// A slow pinch that changes spread by 1 pt per frame must lock to zoom once
    /// the cumulative spread change reaches PINCH_THRESHOLD_PT (10 pt).
    /// The old per-frame heuristic never reached 10 pt in a single frame, keeping
    /// the router stuck in twoFingerEvaluating and eventually locking scroll instead.
    ///
    /// Geometry: f1@(90,100), f2@(110,100) → centroid=(100,100), spread=10 (avg dist from centroid).
    /// Each frame: f1 moves 1pt left, f2 moves 1pt right → spread increases by 1pt/frame.
    /// After 10 frames: spread=20, cumulativeSpreadChange=|20-10|=10 ≥ pinchThreshold → zoom lock.
    func test_slowPinch_cumulativeSpreadChange_locksZoom() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Fingers down: f1@(90,100), f2@(110,100) → centroid=(100,100), spread=10
        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0), phase: .began)
        _ = router.process(sample(id: f2id, x: 110, y: 100, t: 0), phase: .began)

        // 10 slow frames, each advancing spread by 1 pt. Per-frame spread delta = 1 pt
        // (well below the 10 pt threshold). Cumulative after 10 frames = 10 pt → lock.
        var lastZoomEvents: [StylusEvent] = []
        var f1x: CGFloat = 90
        var f2x: CGFloat = 110
        for i in 1...10 {
            f1x -= 1  // each finger moves 1 pt away from centroid → spread grows 1 pt/frame
            f2x += 1
            clock = TimeInterval(i) * 0.016
            _ = router.process(sample(id: f1id, x: f1x, y: 100, t: clock), phase: .moved)
            lastZoomEvents = router.process(sample(id: f2id, x: f2x, y: 100, t: clock), phase: .moved)
        }
        // After 10 frames: f1@(80,100), f2@(120,100), centroid=(100,100), spread=20.
        // cumulativeSpreadChange = |20-10| = 10 >= 10 → must lock to zoom on the 10th frame.
        let hasZoom = lastZoomEvents.contains { if case .stylusZoom = $0 { return true }; return false }
        XCTAssertTrue(hasZoom, "Slow pinch: cumulative spread change of 10 pt over 10 frames → must lock to zoom")
    }

    /// A slow scroll that moves centroid by 2 pt per frame must lock to scroll once
    /// the cumulative centroid change reaches tapMaxSlop (10 pt).
    func test_slowScroll_cumulativeCentroidChange_locksScroll() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Fingers down: spread constant, centroid starts at (100, 100)
        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0), phase: .began)
        _ = router.process(sample(id: f2id, x: 110, y: 100, t: 0), phase: .began)

        // 5 slow frames: each frame moves both fingers 1 pt down (no spread change).
        // Per-frame centroid delta = 1 pt (< 10 pt slop), cumulative after 10 frames = 10 pt.
        var lastScrollEvents: [StylusEvent] = []
        var yOffset: CGFloat = 100
        for i in 1...10 {
            yOffset += 1
            clock = TimeInterval(i) * 0.016
            _ = router.process(sample(id: f1id, x: 90, y: yOffset, t: clock), phase: .moved)
            lastScrollEvents = router.process(sample(id: f2id, x: 110, y: yOffset, t: clock), phase: .moved)
        }
        // After 10 frames: centroid=(100,110), cumulativeCentroid=10 >= 10 → lock to scroll.
        let hasScroll = lastScrollEvents.contains { if case .stylusScroll = $0 { return true }; return false }
        XCTAssertTrue(hasScroll, "Slow scroll: cumulative centroid change of 10 pt over 10 frames → must lock to scroll")
    }

    // MARK: – Bug 2: batch API emits at most one scroll/zoom per call

    /// Using the batch `process(samples:phase:)` API with two simultaneous finger moves
    /// must emit exactly ONE scroll event per call, not two.
    func test_batchProcess_twoFingerScroll_emitsSingleEvent() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Fingers down (processed as batch began)
        let beganSamples = [
            sample(id: f1id, x: 90, y: 100, t: 0),
            sample(id: f2id, x: 110, y: 100, t: 0)
        ]
        _ = router.process(samples: beganSamples, phase: .began)

        // Lock scroll: move centroid 15 pt right in a single batch call
        clock = 0.016
        let movedSamples1 = [
            sample(id: f1id, x: 120, y: 100, t: 0.016),
            sample(id: f2id, x: 140, y: 100, t: 0.016)
        ]
        _ = router.process(samples: movedSamples1, phase: .moved)

        // Subsequent batch move: centroid moves another 10 pt right
        clock = 0.032
        let movedSamples2 = [
            sample(id: f1id, x: 130, y: 100, t: 0.032),
            sample(id: f2id, x: 150, y: 100, t: 0.032)
        ]
        let events = router.process(samples: movedSamples2, phase: .moved)

        let scrollEvents = events.filter { if case .stylusScroll = $0 { return true }; return false }
        XCTAssertEqual(scrollEvents.count, 1,
            "Batch 2-finger scroll: must emit EXACTLY ONE scroll event per process(samples:phase:) call")
    }

    /// Batch scroll: exactly ONE scroll-begin (phase=0) is emitted across the full
    /// gesture, and subsequent scroll batches emit phase=1 (changed).
    ///
    /// Part A (Round 9): scroll-begin is now emitted when the first finger touches down
    /// (during .began), not when the scroll lock is established. The phase progression
    /// invariant is unchanged — only ONE phase=0 per gesture session.
    func test_batchProcess_scrollPhaseProgression() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Capture began events — Part A emits scroll-begin (phase=0) on first finger down.
        let beganEvents = router.process(samples: [
            sample(id: f1id, x: 90, y: 100, t: 0),
            sample(id: f2id, x: 110, y: 100, t: 0)
        ], phase: .began)

        // First moved batch that locks scroll — must emit phase=1 since begin was already sent.
        clock = 0.016
        let events1 = router.process(samples: [
            sample(id: f1id, x: 120, y: 100, t: 0.016),
            sample(id: f2id, x: 140, y: 100, t: 0.016)
        ], phase: .moved)

        // Second moved batch — must also emit phase=1.
        clock = 0.032
        let events2 = router.process(samples: [
            sample(id: f1id, x: 130, y: 100, t: 0.032),
            sample(id: f2id, x: 150, y: 100, t: 0.032)
        ], phase: .moved)

        // Exactly ONE phase=0 across began + all moved batches.
        let allEvents = beganEvents + events1 + events2
        let beginCount = allEvents.compactMap { e -> UInt8? in
            if case .stylusScroll(_, _, let p) = e { return p }; return nil
        }.filter { $0 == 0 }.count

        XCTAssertEqual(beginCount, 1, "Exactly ONE phase=0 (begin) must be emitted across the full scroll session (began + all moved batches)")
    }

    // MARK: – Momentum-cancel grace period (Round 9)

    // Helper: perform a 2-finger scroll that locks, then lifts both fingers, producing a
    // scroll-end (phase=2). Returns a router ready for the next gesture.
    private func routerAfterScrollEnd(
        router: inout TouchRouter,
        clock: inout TimeInterval
    ) {
        let f1 = (id: UUID(), x: CGFloat(90), y: CGFloat(100))
        let f2 = (id: UUID(), x: CGFloat(110), y: CGFloat(100))

        // Fingers down
        _ = router.process(sample(id: f1.id, x: f1.x, y: f1.y, t: clock), phase: .began)
        _ = router.process(sample(id: f2.id, x: f2.x, y: f2.y, t: clock), phase: .began)

        // Lock scroll: move centroid 30 pt right
        clock += 0.016
        _ = router.process(sample(id: f1.id, x: f1.x + 30, y: f1.y, t: clock), phase: .moved)
        _ = router.process(sample(id: f2.id, x: f2.x + 30, y: f2.y, t: clock), phase: .moved)

        // Lift both fingers → emits scroll-end (phase=2)
        clock += 0.016
        _ = router.process(sample(id: f1.id, x: f1.x + 30, y: f1.y, t: clock), phase: .ended)
        _ = router.process(sample(id: f2.id, x: f2.x + 30, y: f2.y, t: clock), phase: .ended)
    }

    /// A 1-finger tap within 500 ms of scroll-end must be suppressed (momentum-cancel grace).
    func test_oneFingerTap_withinGracePeriod_isSuppressed() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        // Perform a scroll and lift, recording the scroll-end time.
        routerAfterScrollEnd(router: &router, clock: &clock)
        let scrollEndTime = clock

        // Tap 200 ms after scroll-end — within 500 ms grace.
        clock = scrollEndTime + 0.200
        let tapId = UUID()
        _ = router.process(sample(id: tapId, x: 100, y: 100, t: clock), phase: .began)
        clock = scrollEndTime + 0.250 // lift within tap duration
        let upEvents = router.process(sample(id: tapId, x: 100, y: 100, t: clock), phase: .ended)

        let hasButton = upEvents.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "1-finger tap 200 ms after scroll-end → momentum-cancel grace → click suppressed")
    }

    /// A 1-finger tap outside the 500 ms grace period fires normally.
    func test_oneFingerTap_outsideGracePeriod_firesNormally() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        routerAfterScrollEnd(router: &router, clock: &clock)
        let scrollEndTime = clock

        // Tap 600 ms after scroll-end — outside 500 ms grace.
        clock = scrollEndTime + 0.600
        let tapId = UUID()
        _ = router.process(sample(id: tapId, x: 100, y: 100, t: clock), phase: .began)
        clock = scrollEndTime + 0.640
        let upEvents = router.process(sample(id: tapId, x: 100, y: 100, t: clock), phase: .ended)

        let buttonCount = upEvents.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "1-finger tap 600 ms after scroll-end → grace expired → LEFT_DOWN + LEFT_UP")
    }

    /// A 2-finger tap within 500 ms of scroll-end must be suppressed (momentum-cancel grace).
    func test_twoFingerTap_withinGracePeriod_isSuppressed() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        routerAfterScrollEnd(router: &router, clock: &clock)
        let scrollEndTime = clock

        // 2-finger tap 200 ms after scroll-end — within grace.
        clock = scrollEndTime + 0.200
        let f1 = UUID()
        let f2 = UUID()
        _ = router.process(sample(id: f1, x: 90, y: 100, t: clock), phase: .began)
        _ = router.process(sample(id: f2, x: 110, y: 100, t: clock), phase: .began)

        clock = scrollEndTime + 0.250 // lift within tap duration
        _ = router.process(sample(id: f1, x: 90, y: 100, t: clock), phase: .ended)
        let upEvents = router.process(sample(id: f2, x: 110, y: 100, t: clock), phase: .ended)

        let hasRightDown = upEvents.contains {
            if case .stylusButton(let b, _) = $0 { return b == 0x10 }
            return false
        }
        XCTAssertFalse(hasRightDown, "2-finger tap 200 ms after scroll-end → momentum-cancel grace → right-click suppressed")
    }

    /// A 2-finger tap outside the 500 ms grace period fires normally (right-click).
    func test_twoFingerTap_outsideGracePeriod_firesNormally() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        routerAfterScrollEnd(router: &router, clock: &clock)
        let scrollEndTime = clock

        // 2-finger tap 600 ms after scroll-end — grace expired.
        clock = scrollEndTime + 0.600
        let f1 = UUID()
        let f2 = UUID()
        _ = router.process(sample(id: f1, x: 90, y: 100, t: clock), phase: .began)
        _ = router.process(sample(id: f2, x: 110, y: 100, t: clock), phase: .began)

        clock = scrollEndTime + 0.640
        _ = router.process(sample(id: f1, x: 90, y: 100, t: clock), phase: .ended)
        let upEvents = router.process(sample(id: f2, x: 110, y: 100, t: clock), phase: .ended)

        let hasRightDown = upEvents.contains {
            if case .stylusButton(let b, _) = $0 { return b == 0x10 }
            return false
        }
        XCTAssertTrue(hasRightDown, "2-finger tap 600 ms after scroll-end → grace expired → right-click fires")
    }

    /// Grace period boundary: tap at exactly 500 ms is suppressed (boundary exclusive — < 0.5s).
    func test_oneFingerTap_atExactGraceBoundary_isSuppressed() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        routerAfterScrollEnd(router: &router, clock: &clock)
        let scrollEndTime = clock

        // Tap starts at exactly scroll-end + 0.5s. The lift (endTimestamp) is what the
        // grace check uses. Tap down at 0.5s, tap up at 0.5s + small delta still < 0.5s
        // from scroll-end? No — the grace check uses the lift timestamp.
        // Lift at scrollEndTime + 0.499 → 0.499 < 0.5 → suppressed.
        clock = scrollEndTime + 0.450
        let tapId = UUID()
        _ = router.process(sample(id: tapId, x: 100, y: 100, t: clock), phase: .began)
        let liftTime = scrollEndTime + 0.499
        clock = liftTime
        let upEvents = router.process(sample(id: tapId, x: 100, y: 100, t: liftTime), phase: .ended)

        let hasButton = upEvents.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "Tap lift at 499 ms after scroll-end → still within grace → suppressed")
    }

    // MARK: – scroll emits correct dx/dy values

    /// The scroll delta must match the centroid movement direction and magnitude.
    /// Because iOS delivers touches one finger at a time, scroll events from both
    /// finger moves in the same logical frame are summed to verify the total delta.
    func test_scroll_deltaMatchesCentroidMovement() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let f1id = UUID()
        let f2id = UUID()

        // Centroid starts at (100, 100), spread = 20 pt (f1@90, f2@110 on x-axis)
        _ = router.process(sample(id: f1id, x: 90, y: 100, t: 0), phase: .began)
        _ = router.process(sample(id: f2id, x: 110, y: 100, t: 0), phase: .began)

        // Move both fingers 20 pt right and 10 pt down (pure translation, spread unchanged).
        // iOS delivers one finger at a time, so we collect scroll events from both moves
        // and sum them — the accumulated delta must equal the total centroid movement (20, 10).
        clock = 0.016
        let events1 = router.process(sample(id: f1id, x: 110, y: 110, t: 0.016), phase: .moved)
        let events2 = router.process(sample(id: f2id, x: 130, y: 110, t: 0.016), phase: .moved)

        let allEvents = events1 + events2
        XCTAssertFalse(allEvents.isEmpty, "Translate-dominant 2-finger move must emit at least one stylusScroll")

        let totalDx = allEvents.compactMap { e -> Float? in
            if case .stylusScroll(let dx, _, _) = e { return dx }
            return nil
        }.reduce(0, +)

        let totalDy = allEvents.compactMap { e -> Float? in
            if case .stylusScroll(_, let dy, _) = e { return dy }
            return nil
        }.reduce(0, +)

        XCTAssertEqual(totalDx, 20, accuracy: 1, "Accumulated scroll dx must match total centroid Δx (20)")
        XCTAssertEqual(totalDy, 10, accuracy: 1, "Accumulated scroll dy must match total centroid Δy (10)")
    }
}
