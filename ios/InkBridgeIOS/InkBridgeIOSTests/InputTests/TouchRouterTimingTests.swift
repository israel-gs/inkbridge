import XCTest
@testable import InkBridgeIOS

// MARK: - E.5 Timing — 350 ms double-tap-drag window
// ClockBox is defined in TestHelpers.swift (shared across InputTests target)

final class TouchRouterTimingTests: XCTestCase {

    private func sample(
        id: UUID = UUID(),
        x: CGFloat = 100,
        y: CGFloat = 100,
        t: TimeInterval
    ) -> TouchSample {
        TouchSample(id: id, location: CGPoint(x: x, y: y), timestamp: t)
    }

    // Perform a clean first tap: down at t=0, up at t=100ms.
    // Returns a router in doubleTapDragArmed state, with the clock box at 0.100.
    private func routerAfterFirstTap(clockBox: ClockBox) -> TouchRouter {
        var router = TouchRouter(now: { clockBox.value })
        let id = UUID()
        clockBox.value = 0
        _ = router.process(sample(id: id, x: 100, y: 100, t: clockBox.value), phase: .began)
        clockBox.value = 0.100
        _ = router.process(sample(id: id, x: 100, y: 100, t: clockBox.value), phase: .ended)
        return router
    }

    // MARK: – 349 ms → enters doubleTapDragActive (below window, but still within it)

    /// Second tap down at 349 ms after first tap-up → enters doubleTapDragActive.
    func test_doubleTapDrag_at349ms_isArmed() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)
        // clockBox.value is now 0.100 (first tap up time)

        let id2 = UUID()
        // Gap = 0.349 → second tap starts at 0.100 + 0.349 = 0.449
        clockBox.value = 0.449
        let downEvents = router.process(sample(id: id2, x: 100, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertTrue(hasLeftDown, "Second tap at 349 ms gap → must emit LEFT_DOWN (armed→active)")

        clockBox.value = 0.465
        let moveEvents = router.process(sample(id: id2, x: 110, y: 100, t: clockBox.value), phase: .moved)
        let hasDelta = moveEvents.contains { if case .cursorDelta = $0 { return true }; return false }
        XCTAssertTrue(hasDelta, "Moving during doubleTapDragActive must produce cursor deltas")
    }

    // MARK: – 350 ms → also armed (boundary inclusive)

    func test_doubleTapDrag_at350ms_isArmed_boundaryInclusive() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)

        let id2 = UUID()
        // 0.100 + 0.350 = 0.450
        clockBox.value = 0.450
        let downEvents = router.process(sample(id: id2, x: 100, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertTrue(hasLeftDown, "Second tap at exactly 350 ms → boundary inclusive → armed")
    }

    // MARK: – 351 ms → new tap (outside window)

    func test_doubleTapDrag_at351ms_isNewTap() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)

        let id2 = UUID()
        // 0.100 + 0.351 = 0.451
        clockBox.value = 0.451
        let downEvents = router.process(sample(id: id2, x: 100, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertFalse(hasLeftDown, "Second tap at 351 ms → outside window → new tap (no LEFT_DOWN on down)")

        // Lifting within 250 ms → regular tap
        clockBox.value = 0.551
        let upEvents = router.process(sample(id: id2, x: 100, y: 100, t: clockBox.value), phase: .ended)
        let buttonCount = upEvents.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "New tap outside window → regular tap emits LEFT_DOWN + LEFT_UP on lift")
    }

    // MARK: – Injected clock is used (not real time)

    func test_injectedClock_isUsed() {
        let clockBox = ClockBox(1_000_000)
        var router = TouchRouter(now: { clockBox.value })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: clockBox.value), phase: .began)
        let events = router.process(sample(id: id, x: 100, y: 100, t: clockBox.value), phase: .ended)
        let buttonCount = events.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "Router uses injected clock — frozen time still produces a tap")
    }
}
