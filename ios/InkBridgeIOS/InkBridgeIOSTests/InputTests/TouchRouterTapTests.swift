import XCTest
@testable import InkBridgeIOS

// MARK: - E.1 Tap / drag base cases

final class TouchRouterTapTests: XCTestCase {

    // Convenience: produce a TouchSample at a given (x,y) and timestamp.
    private func sample(
        id: UUID = UUID(),
        x: CGFloat = 100,
        y: CGFloat = 100,
        t: TimeInterval
    ) -> TouchSample {
        TouchSample(id: id, location: CGPoint(x: x, y: y), timestamp: t)
    }

    // MARK: – 1-finger tap

    /// A touch that begins and ends within 250 ms with movement < 10 pt must emit
    /// LEFT_DOWN then LEFT_UP (in that order).
    ///
    /// Part A (Round 9): finger-down now also emits a zero-delta scroll-begin to cancel
    /// Mac momentum immediately. The button pair still fires on lift as before.
    func test_oneFingerTap_emitsLeftDownThenLeftUp() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let fingerId = UUID()
        // begin — emits a momentum-cancel scroll-begin (phase=0, delta=0) but no button events
        let down = sample(id: fingerId, x: 100, y: 100, t: 0)
        let eventsDown = router.process(down, phase: .began)
        let hasScrollBegin = eventsDown.contains {
            if case .stylusScroll(let dx, let dy, let p) = $0 { return dx == 0 && dy == 0 && p == 0 }
            return false
        }
        XCTAssertTrue(hasScrollBegin, "Finger-down must emit a zero-delta scroll-begin (momentum-cancel hint)")
        let hasButtonOnDown = eventsDown.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButtonOnDown, "No button events on finger-down — they fire on lift")

        // end within 240 ms, same location
        clock = 0.240
        let up = sample(id: fingerId, x: 100, y: 100, t: 0.240)
        let eventsUp = router.process(up, phase: .ended)

        XCTAssertEqual(eventsUp.count, 2, "Tap must emit exactly two events on lift")
        // Wire-format: 0x08 = BUTTON_PRIMARY (bit 3 of flags/buttons field per protocol §Flags).
        XCTAssertEqual(eventsUp[0], .stylusButton(buttons: 0x08, primaryDown: true),  "First event: LEFT_DOWN")
        XCTAssertEqual(eventsUp[1], .stylusButton(buttons: 0x00, primaryDown: false), "Second event: LEFT_UP")
    }

    /// A tap at exactly the 250 ms boundary is still a tap (boundary inclusive).
    func test_oneFingerTap_atExactly250ms_isTap() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, t: 0), phase: .began)
        clock = 0.250
        let events = router.process(sample(id: id, x: 100, y: 100, t: 0.250), phase: .ended)

        XCTAssertEqual(events.count, 2, "Exactly 250 ms → still a tap")
    }

    /// A touch that ends after 251 ms is a drag (too slow for tap) — no button events.
    func test_oneFingerTap_after251ms_isNotTap() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, t: 0), phase: .began)
        clock = 0.251
        let events = router.process(sample(id: id, x: 100, y: 100, t: 0.251), phase: .ended)

        let hasButton = events.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "Duration > 250 ms → drag, no button events")
    }

    // MARK: – Drag disqualifies tap

    /// Movement > 10 pt during a 1-finger touch means it's a drag: no button events on lift.
    func test_oneFingerDrag_beyondSlop_emitsNOButtonEvents() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)

        // Move 15 pt (well beyond 10 pt slop)
        clock = 0.050
        _ = router.process(sample(id: id, x: 115, y: 100, t: 0.050), phase: .moved)

        clock = 0.100
        let upEvents = router.process(sample(id: id, x: 115, y: 100, t: 0.100), phase: .ended)

        let hasButton = upEvents.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "Drag > 10 pt → no button event on lift")
    }

    /// Movement of exactly 10 pt is within slop (boundary inclusive) — still qualifies as tap.
    func test_oneFingerTap_exactlyAtSlop_isTap() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clock = 0.050
        _ = router.process(sample(id: id, x: 110, y: 100, t: 0.050), phase: .moved) // exactly 10 pt
        clock = 0.100
        let events = router.process(sample(id: id, x: 110, y: 100, t: 0.100), phase: .ended)

        let buttonCount = events.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "Movement = 10 pt → still within slop, emits LEFT_DOWN + LEFT_UP")
    }

    /// Movement of 11 pt exceeds slop — drag, no button events.
    func test_oneFingerTap_11ptMovement_isNotTap() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clock = 0.050
        _ = router.process(sample(id: id, x: 111, y: 100, t: 0.050), phase: .moved) // 11 pt
        clock = 0.100
        let events = router.process(sample(id: id, x: 111, y: 100, t: 0.100), phase: .ended)

        let hasButton = events.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "Movement = 11 pt → drag, no button events")
    }

    // MARK: – Drag emits cursor deltas

    /// A 1-finger drag emits cursorDelta events but no button events.
    func test_oneFingerDrag_emitsCursorDeltas() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)

        clock = 0.016
        let moveEvents = router.process(sample(id: id, x: 110, y: 105, t: 0.016), phase: .moved)

        let deltas = moveEvents.compactMap { event -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = event { return (dx, dy) }
            return nil
        }
        XCTAssertFalse(deltas.isEmpty, "1-finger drag must emit at least one cursorDelta")
    }

    // MARK: – touchCancelled releases held button

    /// If a finger is in a drag and the touch is cancelled, any held button must be released.
    /// For a tap-in-progress (oneFingerActive), cancelling should also clean up state.
    func test_touchCancelled_whileOneFingerActive_cleansState() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clock = 0.010
        let cancelEvents = router.process(sample(id: id, x: 100, y: 100, t: 0.010), phase: .cancelled)

        // After cancel, the router must be back in idle — a subsequent tap should work normally.
        let id2 = UUID()
        _ = router.process(sample(id: id2, x: 50, y: 50, t: 0.100), phase: .began)
        clock = 0.200
        let tapEvents = router.process(sample(id: id2, x: 50, y: 50, t: 0.200), phase: .ended)

        let buttonCount = tapEvents.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "After cancel + new tap, router must still fire LEFT_DOWN+UP")

        // The cancel itself must not emit a DOWN without a matching UP.
        let downEvents = cancelEvents.filter {
            if case .stylusButton(_, let d) = $0 { return d }; return false
        }
        XCTAssertEqual(downEvents.count, 0, "Cancel must not emit an unmatched DOWN")
    }

    /// If the router is in doubleTapDragActive (button held down) and touch is cancelled,
    /// it must emit LEFT_UP to release the held button.
    func test_touchCancelled_duringDoubleTapDragActive_emitsButtonUp() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        // First tap
        let id1 = UUID()
        _ = router.process(sample(id: id1, x: 100, y: 100, t: 0), phase: .began)
        clock = 0.100
        _ = router.process(sample(id: id1, x: 100, y: 100, t: 0.100), phase: .ended)

        // Second tap within 350 ms, within 20 pt → enters doubleTapDragArmed then doubleTapDragActive
        let id2 = UUID()
        clock = 0.200
        _ = router.process(sample(id: id2, x: 100, y: 100, t: 0.200), phase: .began)

        // Now cancel while holding
        clock = 0.250
        let cancelEvents = router.process(sample(id: id2, x: 100, y: 100, t: 0.250), phase: .cancelled)

        let hasUp = cancelEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x00 && !d }
            return false
        }
        XCTAssertTrue(hasUp, "Cancel during doubleTapDragActive must emit LEFT_UP to release button")
    }
}
