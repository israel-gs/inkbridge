import XCTest
import CoreGraphics
@testable import InkBridgeCore

/// Tests for ``InkBridgeServer``. Phase 3.5.
///
/// Uses ``NoOpListener`` + ``MockInjector`` so no real ports are bound
/// and no CGEvents are posted.
@MainActor
final class InkBridgeServerTests: XCTestCase {

    private var udpListener: NoOpListener!
    private var tcpListener: NoOpListener!
    private var injector: MockInjector!
    private var server: InkBridgeServer!
    private let display = DisplayRect(width: 1920, height: 1080)

    override func setUp() async throws {
        try await super.setUp()
        udpListener = NoOpListener()
        tcpListener = NoOpListener()
        injector = MockInjector()
        server = InkBridgeServer(
            injector: injector,
            udpListener: udpListener,
            tcpListener: tcpListener,
            displayRect: display
        )
    }

    override func tearDown() async throws {
        server.stop()
        server = nil
        injector = nil
        udpListener = nil
        tcpListener = nil
        try await super.tearDown()
    }

    // MARK: - Helper

    private func makeMoveFrame(x: Float, y: Float, seq: UInt32 = 0) throws -> DecodedFrame {
        let data = try BinaryStylusCodec.encode(
            .move(x: x, y: y, pressure: 10000, tiltX: 0, tiltY: 0),
            flags: Flags.pressurePresent,
            sequence: seq,
            timestampNs: 0
        )
        return try BinaryStylusCodec.decode(data)
    }

    // MARK: - State transitions

    func testStartSetsListeningState() {
        server.start(port: 4545)
        if case .listening(let p) = server.state {
            XCTAssertEqual(p, 4545)
        } else {
            XCTFail("Expected .listening, got \(server.state)")
        }
    }

    func testStopSetsIdleState() {
        server.start(port: 4545)
        server.stop()
        XCTAssertEqual(server.state, .idle)
    }

    // MARK: - Frame processing

    func testMoveFrameFromUDPReachesInjector() async throws {
        server.start(port: 4545)
        // Give async tasks a moment to start.
        try await Task.sleep(nanoseconds: 50_000_000)

        let frame = try makeMoveFrame(x: 0.5, y: 0.5)
        udpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 1)
        // Expected point: 0.5 × 1920 = 960, 0.5 × 1080 = 540.
        XCTAssertEqual(injector.calls[0].1.x, 960, accuracy: 1)
        XCTAssertEqual(injector.calls[0].1.y, 540, accuracy: 1)
    }

    func testMoveFrameFromTCPReachesInjector() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let frame = try makeMoveFrame(x: 0.25, y: 0.75)
        tcpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].1.x, 480, accuracy: 1)    // 0.25 × 1920
        XCTAssertEqual(injector.calls[0].1.y, 810, accuracy: 1)    // 0.75 × 1080
    }

    func testProximityFrameReachesInjector() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .proximity(entering: true),
            flags: Flags.hover,
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 1)
        guard case .proximity(let entering) = injector.calls[0].0 else {
            return XCTFail("Expected proximity event")
        }
        XCTAssertTrue(entering)
    }

    /// Regression: without last-point tracking, BUTTON frames inject at (0,0) and
    /// a primary press opens the Apple menu in the top-left corner of the display.
    func testButtonFrameUsesLastMovePoint() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        // First: a MOVE at (0.25, 0.75) → 480, 810.
        udpListener.emit(try makeMoveFrame(x: 0.25, y: 0.75))
        try await Task.sleep(nanoseconds: 50_000_000)

        // Then: a BUTTON_DOWN frame (no coordinates in its payload).
        let buttonData = try BinaryStylusCodec.encode(
            .button(buttons: 0x08),
            flags: 0x08,
            sequence: 1,
            timestampNs: 0
        )
        let buttonFrame = try BinaryStylusCodec.decode(buttonData)
        udpListener.emit(buttonFrame)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 2)
        // Button call must have landed at the MOVE point, NOT at (0, 0).
        XCTAssertEqual(injector.calls[1].1.x, 480, accuracy: 1)
        XCTAssertEqual(injector.calls[1].1.y, 810, accuracy: 1)
    }

    /// Without any prior MOVE, BUTTON falls back to the display center, not (0,0).
    func testButtonFrameBeforeAnyMoveUsesDisplayCenter() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let buttonData = try BinaryStylusCodec.encode(
            .button(buttons: 0x08),
            flags: 0x08,
            sequence: 0,
            timestampNs: 0
        )
        let buttonFrame = try BinaryStylusCodec.decode(buttonData)
        udpListener.emit(buttonFrame)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 1)
        XCTAssertEqual(injector.calls[0].1.x, 960, accuracy: 1)  // 1920 / 2
        XCTAssertEqual(injector.calls[0].1.y, 540, accuracy: 1)  // 1080 / 2
    }

    func testStatsIncrementOnFrame() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.stats.packetsReceived, 0)

        udpListener.emit(try makeMoveFrame(x: 0.1, y: 0.1))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.stats.packetsReceived, 1)
    }

    // MARK: - Latency tracker integration

    func testLatencySnapshotUpdatesAfterFrame() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.latency.samples, 0)

        udpListener.emit(try makeMoveFrame(x: 0.5, y: 0.5))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.latency.samples, 1)
        // arrivalToInject is Mac-internal and must be ≥ 0 ms.
        XCTAssertGreaterThanOrEqual(server.latency.arrivalToInjectP50Ms, 0)
    }

    func testLatencyAccumulatesAcrossMultipleFrames() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        for i in 0..<5 {
            udpListener.emit(try makeMoveFrame(x: Float(i) * 0.1, y: 0.5, seq: UInt32(i)))
            // Small delay per frame so each crosses the 100ms throttle boundary
            // on at least the first and last frames; drives a fresh `snapshot()`
            // publish. (Tracker records every frame, publishes are throttled.)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        // Wait past the throttle so the final frame's snapshot publishes.
        try await Task.sleep(nanoseconds: 150_000_000)
        // Force a final frame to trigger the throttled publish of all 5 samples.
        udpListener.emit(try makeMoveFrame(x: 0.5, y: 0.5, seq: 99))
        try await Task.sleep(nanoseconds: 50_000_000)

        // After 6 records + throttled publish, latency.samples should equal 6.
        XCTAssertEqual(server.latency.samples, 6)
    }

    // MARK: - Gesture events (scroll / zoom)

    func testScrollFrameCallsInjectScroll() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .scroll(deltaX: 0, deltaY: 30),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        // Scroll must NOT appear in inject() calls (it's a different path).
        XCTAssertEqual(injector.calls.count, 0)
        XCTAssertEqual(injector.scrollCalls.count, 1)
        XCTAssertEqual(injector.scrollCalls[0].0, 0)    // deltaX
        XCTAssertEqual(injector.scrollCalls[0].1, 30)   // deltaY
    }

    func testZoomFrameCallsInjectZoom() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .zoom(scaleDelta: 1.10),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.calls.count, 0)
        XCTAssertEqual(injector.zoomCalls.count, 1)
        XCTAssertEqual(injector.zoomCalls[0], 1.10, accuracy: 1e-6)
    }

    func testScrollDoesNotUpdateLastPoint() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Move to establish a known lastPoint.
        udpListener.emit(try makeMoveFrame(x: 0.25, y: 0.75))
        try await Task.sleep(nanoseconds: 50_000_000)

        // Emit a scroll — must NOT touch lastPoint.
        let scrollData = try BinaryStylusCodec.encode(
            .scroll(deltaX: 5, deltaY: 10),
            flags: 0x00,
            sequence: 1,
            timestampNs: 0
        )
        udpListener.emit(try BinaryStylusCodec.decode(scrollData))
        try await Task.sleep(nanoseconds: 50_000_000)

        // Follow with a button — must still land at the MOVE point, not (0,0).
        let buttonData = try BinaryStylusCodec.encode(
            .button(buttons: 0x08),
            flags: 0x08,
            sequence: 2,
            timestampNs: 0
        )
        udpListener.emit(try BinaryStylusCodec.decode(buttonData))
        try await Task.sleep(nanoseconds: 50_000_000)

        // inject() calls: 1 MOVE + 1 BUTTON (scroll bypasses inject())
        XCTAssertEqual(injector.calls.count, 2)
        // Button must land at 0.25 × 1920 = 480, 0.75 × 1080 = 810.
        XCTAssertEqual(injector.calls[1].1.x, 480, accuracy: 1)
        XCTAssertEqual(injector.calls[1].1.y, 810, accuracy: 1)
    }

    // MARK: - A5: Scroll phase routing

    /// SCROLL frame with flags=0x40 (SCROLL_BEGIN) → injector.scrollCalls last entry has phaseFlags=0x40.
    func testScrollFrameWithBeginFlagPassesPhaseFlags0x40() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .scroll(deltaX: 5, deltaY: 10),
            flags: 0x40,   // SCROLL_BEGIN
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.scrollCalls.count, 1)
        XCTAssertEqual(injector.scrollCalls[0].2, 0x40, "phaseFlags must be 0x40 for SCROLL_BEGIN")
    }

    /// SCROLL frame with flags=0x80 (SCROLL_END) → injector.scrollCalls last entry has phaseFlags=0x80.
    func testScrollFrameWithEndFlagPassesPhaseFlags0x80() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .scroll(deltaX: 0, deltaY: 5),
            flags: 0x80,   // SCROLL_END
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.scrollCalls.count, 1)
        XCTAssertEqual(injector.scrollCalls[0].2, 0x80, "phaseFlags must be 0x80 for SCROLL_END")
    }

    /// CURSOR_DELTA frame → injector.cursorDeltaCalls increments.
    func testCursorDeltaFrameCallsInjectCursorDelta() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let data = try BinaryStylusCodec.encode(
            .cursorDelta(deltaX: 3, deltaY: -2),
            flags: 0x00,
            sequence: 0,
            timestampNs: 0
        )
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.cursorDeltaCalls.count, 1, "cursorDelta must reach injector.cursorDeltaCalls")
        XCTAssertEqual(injector.cursorDeltaCalls[0].0, 3)
        XCTAssertEqual(injector.cursorDeltaCalls[0].1, -2)
        // inject() must NOT be called for cursorDelta.
        XCTAssertEqual(injector.calls.count, 0, "cursorDelta must not go through inject()")
    }

    /// InjectorError.notTrusted on a MOVE frame → state transitions to .degraded.
    func testNotTrustedErrorTransitionsToDegraded() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        injector.nextError = .notTrusted
        udpListener.emit(try makeMoveFrame(x: 0.5, y: 0.5))
        try await Task.sleep(nanoseconds: 50_000_000)

        if case .degraded = server.state {
            // Pass — correct transition.
        } else {
            XCTFail("Expected .degraded after InjectorError.notTrusted, got \(server.state)")
        }
    }

    func testInjectionFailureDoesNotChangeState() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        injector.nextError = .eventCreationFailed
        udpListener.emit(try makeMoveFrame(x: 0.5, y: 0.5))

        try await Task.sleep(nanoseconds: 50_000_000)

        // State must remain .listening — R8.
        if case .listening = server.state {
            // Pass
        } else {
            XCTFail("Expected .listening after injection failure, got \(server.state)")
        }
        // Injection failure increments injectionFailures, not packetsDropped.
        // packetsDropped tracks listener/decode errors; injectionFailures tracks OS rejections.
        XCTAssertEqual(server.stats.injectionFailures, 1)
    }

    // MARK: - Bug 4: Stats counter separation

    /// packetsDropped increments only for listener/decode errors, NOT for injection failures.
    func testPacketsDroppedDoesNotIncrementOnInjectionFailure() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        injector.nextError = .eventCreationFailed
        udpListener.emit(try makeMoveFrame(x: 0.5, y: 0.5))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.stats.packetsDropped, 0,
            "packetsDropped must be 0 — injection failures go to injectionFailures")
        XCTAssertEqual(server.stats.injectionFailures, 1,
            "injectionFailures must be 1 after one injection error")
    }

    /// Listener-level errors (e.g. decode failure via error stream) increment packetsDropped,
    /// not injectionFailures.
    func testPacketsDroppedIncrementsOnListenerError() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate a listener-level error by emitting to the error stream directly.
        udpListener.emitError(ProtocolError.unknownType(got: 0xFF))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(server.stats.packetsDropped, 1,
            "packetsDropped must increment on listener/decode errors")
        XCTAssertEqual(server.stats.injectionFailures, 0,
            "injectionFailures must be 0 for listener errors")
    }

    /// Stats.bytesReceived has been removed (was never incremented). Verify the struct
    /// compiles and initialises correctly with the new field set.
    func testStatsBytesReceivedFieldRemoved() {
        let s = Stats(packetsReceived: 1, packetsDropped: 2, injectionFailures: 3)
        XCTAssertEqual(s.packetsReceived, 1)
        XCTAssertEqual(s.packetsDropped, 2)
        XCTAssertEqual(s.injectionFailures, 3)
    }
}
