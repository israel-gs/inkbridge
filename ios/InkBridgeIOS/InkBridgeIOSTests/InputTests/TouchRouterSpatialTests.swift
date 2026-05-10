import XCTest
@testable import InkBridgeIOS

// MARK: - E.7 Spatial boundaries (20 pt tolerance + 10 pt slop)

final class TouchRouterSpatialTests: XCTestCase {

    private func sample(
        id: UUID = UUID(),
        x: CGFloat,
        y: CGFloat,
        t: TimeInterval
    ) -> TouchSample {
        TouchSample(id: id, location: CGPoint(x: x, y: y), timestamp: t)
    }

    // Perform a clean first tap at (100, 100), t=0..100ms.
    // Uses ClockBox (reference type) to allow the @escaping now closure to share the clock.
    private func routerAfterFirstTap(clockBox: ClockBox) -> TouchRouter {
        var router = TouchRouter(now: { clockBox.value })
        let id = UUID()
        clockBox.value = 0
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clockBox.value = 0.100
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0.100), phase: .ended)
        return router
    }

    // MARK: – doubleTapSpatialTolerance = 20 pt

    /// Second tap 19 pt from first → within tolerance → enters doubleTapDragActive.
    func test_doubleTap_19ptAway_isArmed() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)

        let id2 = UUID()
        clockBox.value = 0.300 // 200 ms gap, well within 350 ms window
        let downEvents = router.process(sample(id: id2, x: 119, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertTrue(hasLeftDown, "19 pt from first tap → within tolerance → doubleTapDragActive")
    }

    /// Second tap exactly 20 pt from first → boundary inclusive → doubleTapDragActive.
    func test_doubleTap_20ptAway_isArmed_boundaryInclusive() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)

        let id2 = UUID()
        clockBox.value = 0.300
        let downEvents = router.process(sample(id: id2, x: 120, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertTrue(hasLeftDown, "Exactly 20 pt from first tap → boundary inclusive → armed")
    }

    /// Second tap 21 pt from first → outside tolerance → treated as new independent tap.
    func test_doubleTap_21ptAway_isNewTap() {
        let clockBox = ClockBox()
        var router = routerAfterFirstTap(clockBox: clockBox)

        let id2 = UUID()
        clockBox.value = 0.300
        let downEvents = router.process(sample(id: id2, x: 121, y: 100, t: clockBox.value), phase: .began)

        let hasLeftDown = downEvents.contains {
            if case .stylusButton(let b, let d) = $0 { return b == 0x08 && d }
            return false
        }
        XCTAssertFalse(hasLeftDown, "21 pt from first tap → outside tolerance → new tap (no immediate LEFT_DOWN)")

        clockBox.value = 0.400
        let upEvents = router.process(sample(id: id2, x: 121, y: 100, t: clockBox.value), phase: .ended)
        let buttonCount = upEvents.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "New tap → regular tap emits LEFT_DOWN + LEFT_UP on lift")
    }

    // MARK: – tapMaxSlop = 10 pt (single-tap classification)

    func test_singleTap_9ptMovement_isTap() {
        let clockBox = ClockBox()
        var router = TouchRouter(now: { clockBox.value })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clockBox.value = 0.050
        _ = router.process(sample(id: id, x: 109, y: 100, t: clockBox.value), phase: .moved)
        clockBox.value = 0.100
        let events = router.process(sample(id: id, x: 109, y: 100, t: clockBox.value), phase: .ended)

        let buttonCount = events.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "9 pt movement → within 10 pt slop → still a tap")
    }

    func test_singleTap_10ptMovement_isTap_boundaryInclusive() {
        let clockBox = ClockBox()
        var router = TouchRouter(now: { clockBox.value })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clockBox.value = 0.050
        _ = router.process(sample(id: id, x: 110, y: 100, t: clockBox.value), phase: .moved)
        clockBox.value = 0.100
        let events = router.process(sample(id: id, x: 110, y: 100, t: clockBox.value), phase: .ended)

        let buttonCount = events.filter { if case .stylusButton = $0 { return true }; return false }.count
        XCTAssertEqual(buttonCount, 2, "10 pt movement → boundary inclusive → tap")
    }

    func test_singleTap_11ptMovement_isNotTap() {
        let clockBox = ClockBox()
        var router = TouchRouter(now: { clockBox.value })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)
        clockBox.value = 0.050
        _ = router.process(sample(id: id, x: 111, y: 100, t: clockBox.value), phase: .moved)
        clockBox.value = 0.100
        let events = router.process(sample(id: id, x: 111, y: 100, t: clockBox.value), phase: .ended)

        let hasButton = events.contains { if case .stylusButton = $0 { return true }; return false }
        XCTAssertFalse(hasButton, "11 pt movement → drag, no button events")
    }
}
