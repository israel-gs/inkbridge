import XCTest
@testable import InkBridgeIOS

// MARK: - E.3 Drag deltas + GestureGeometry

final class TouchRouterDragTests: XCTestCase {

    private func sample(
        id: UUID = UUID(),
        x: CGFloat,
        y: CGFloat,
        t: TimeInterval
    ) -> TouchSample {
        TouchSample(id: id, location: CGPoint(x: x, y: y), timestamp: t)
    }

    // MARK: – cursorDelta values match touch movement

    /// dx and dy in the emitted cursorDelta must exactly match the touch movement.
    func test_dragDelta_matchesMovement() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)

        // Move 15 pt right, 8 pt down — beyond slop, so a drag is established.
        clock = 0.016
        let events1 = router.process(sample(id: id, x: 115, y: 108, t: 0.016), phase: .moved)
        let delta1 = events1.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertNotNil(delta1, "Move beyond slop must produce a cursorDelta")
        XCTAssertEqual(delta1?.0, 15, "dx must be 15")
        XCTAssertEqual(delta1?.1, 8,  "dy must be 8")

        // Move 5 more pt right from the new position
        clock = 0.032
        let events2 = router.process(sample(id: id, x: 120, y: 108, t: 0.032), phase: .moved)
        let delta2 = events2.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertNotNil(delta2)
        XCTAssertEqual(delta2?.0, 5, "Incremental dx must be 5")
        XCTAssertEqual(delta2?.1, 0, "Incremental dy must be 0")
    }

    /// Negative movement produces negative deltas.
    func test_dragDelta_negativeValues() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 200, y: 200, t: 0), phase: .began)

        clock = 0.016
        let events = router.process(sample(id: id, x: 185, y: 192, t: 0.016), phase: .moved)
        let delta = events.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.0, -15, "dx must be -15")
        XCTAssertEqual(delta?.1, -8,  "dy must be -8")
    }

    // MARK: – Int16 clamping

    /// A move that would produce dx > Int16.max must be clamped to 32767.
    func test_dragDelta_clampedAtInt16Max() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 0, y: 0, t: 0), phase: .began)

        clock = 0.016
        // Move 40_000 pt to the right — way beyond Int16.max
        let events = router.process(sample(id: id, x: 40_000, y: 0, t: 0.016), phase: .moved)
        let delta = events.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.0, Int16.max, "dx must be clamped at Int16.max (32767)")
        XCTAssertEqual(delta?.1, 0)
    }

    /// A move that would produce dx < Int16.min must be clamped to -32768.
    func test_dragDelta_clampedAtInt16Min() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 40_000, y: 0, t: 0), phase: .began)

        clock = 0.016
        let events = router.process(sample(id: id, x: 0, y: 0, t: 0.016), phase: .moved)
        let delta = events.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.0, Int16.min, "dx must be clamped at Int16.min (-32768)")
    }

    // MARK: – v1 acceleration is identity

    /// In v1, acceleration is the identity function: no curve transformation applied.
    /// Verify by checking that moving N pt yields a delta of exactly N.
    func test_dragDelta_identityAcceleration() {
        var clock: TimeInterval = 0
        var router = TouchRouter(now: { clock })

        let id = UUID()
        _ = router.process(sample(id: id, x: 100, y: 100, t: 0), phase: .began)

        clock = 0.016
        // Move exactly 30 pt
        let events = router.process(sample(id: id, x: 130, y: 100, t: 0.016), phase: .moved)
        let delta = events.compactMap { e -> (Int16, Int16)? in
            if case .cursorDelta(let dx, let dy) = e { return (dx, dy) }
            return nil
        }.first

        XCTAssertEqual(delta?.0, 30, "Identity acceleration: 30 pt movement → delta 30")
    }

    // MARK: – GestureGeometry unit tests

    func test_gestureGeometry_centroid_twoPoints() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let c = GestureGeometry.centroid(pts)
        XCTAssertEqual(c.x, 5, accuracy: 0.001)
        XCTAssertEqual(c.y, 5, accuracy: 0.001)
    }

    func test_gestureGeometry_centroid_singlePoint() {
        let pts = [CGPoint(x: 7, y: 3)]
        let c = GestureGeometry.centroid(pts)
        XCTAssertEqual(c.x, 7, accuracy: 0.001)
        XCTAssertEqual(c.y, 3, accuracy: 0.001)
    }

    func test_gestureGeometry_spread_twoPoints() {
        // Two points at (0,0) and (10,0): centroid = (5,0); each is 5 pt from centroid
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]
        let s = GestureGeometry.spread(pts)
        XCTAssertEqual(s, 5, accuracy: 0.001, "Average distance from centroid must be 5")
    }

    func test_gestureGeometry_distance() {
        let d = GestureGeometry.distance(CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 4))
        XCTAssertEqual(d, 5, accuracy: 0.001, "3-4-5 right triangle")
    }

    func test_gestureGeometry_centroid_empty_isZero() {
        let c = GestureGeometry.centroid([])
        XCTAssertEqual(c.x, 0)
        XCTAssertEqual(c.y, 0)
    }
}
