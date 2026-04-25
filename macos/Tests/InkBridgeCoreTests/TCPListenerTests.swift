import XCTest
import Network
@testable import InkBridgeCore

/// Tests for ``TCPListener``. Phase 3.4.
///
/// Uses port 45452 and loopback NWConnection. The key test sends a frame
/// split across two writes to verify the buffered state machine reassembles it.
final class TCPListenerTests: XCTestCase {

    private static let testPort: UInt16 = 45452
    private var listener: TCPListener!

    override func setUp() {
        super.setUp()
        listener = TCPListener(port: Self.testPort)
    }

    override func tearDown() {
        listener.stop()
        listener = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.testPort)!,
            using: .tcp
        )
    }

    private func connectAndWait(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                default: break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let e = error { cont.resume(throwing: e) } else { cont.resume() }
            })
        }
    }

    private func moveFrame(x: Float, y: Float, seq: UInt32 = 0) throws -> Data {
        try BinaryStylusCodec.encode(
            .move(x: x, y: y, pressure: 2000, tiltX: 50, tiltY: -50),
            flags: Flags.pressurePresent | Flags.tiltPresent,
            sequence: seq,
            timestampNs: 99999
        )
    }

    // MARK: - Tests

    func testListenerReceivesCompleteFrame() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        let data = try moveFrame(x: 0.3, y: 0.7)

        async let firstFrame = listener.frames.first(where: { _ in true })
        try await send(data, on: conn)

        let frame = await firstFrame
        let received = try XCTUnwrap(frame)
        guard case let .move(rx, ry, _, _, _) = received.event else {
            return XCTFail("Expected move event")
        }
        XCTAssertEqual(rx, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ry, 0.7, accuracy: 0.0001)
        conn.cancel()
    }

    func testSplitFrameIsReassembled() async throws {
        // Verifies the buffered state machine handles TCP segmentation. transport.md R4.
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        let data = try moveFrame(x: 0.6, y: 0.4, seq: 1)
        // Split: first 10 bytes, then the rest.
        let part1 = data.prefix(10)
        let part2 = data.dropFirst(10)

        async let firstFrame = listener.frames.first(where: { _ in true })
        try await send(Data(part1), on: conn)
        try await Task.sleep(nanoseconds: 20_000_000)
        try await send(Data(part2), on: conn)

        let frame = await firstFrame
        let received = try XCTUnwrap(frame)
        guard case let .move(rx, ry, _, _, _) = received.event else {
            return XCTFail("Expected move event")
        }
        XCTAssertEqual(rx, 0.6, accuracy: 0.0001)
        XCTAssertEqual(ry, 0.4, accuracy: 0.0001)
        conn.cancel()
    }

    func testTwoConsecutiveFramesDecoded() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        var combined = Data()
        combined.append(try moveFrame(x: 0.1, y: 0.2, seq: 0))
        combined.append(try moveFrame(x: 0.3, y: 0.4, seq: 1))

        var frames: [DecodedFrame] = []
        let collectTask = Task {
            for await frame in self.listener.frames {
                frames.append(frame)
                if frames.count == 2 { break }
            }
        }

        try await send(combined, on: conn)
        try await Task.sleep(nanoseconds: 200_000_000)
        collectTask.cancel()

        XCTAssertEqual(frames.count, 2)
        conn.cancel()
    }

    func testCorruptFrameYieldsError() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        // A 36-byte buffer with bad version (0xFF at byte 0).
        var bad = Data(repeating: 0x00, count: 36)
        bad[0] = 0xFF
        bad[1] = 0x01  // STYLUS_MOVE so payload size is known

        async let firstError = listener.errors.first(where: { _ in true })
        try await send(bad, on: conn)

        let err = await firstError
        XCTAssertNotNil(err)
        conn.cancel()
    }

    func testNewConnectionReplacesExisting() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn1 = makeConnection()
        try await connectAndWait(conn1)

        // A second connection should replace the first. transport.md R4.
        let conn2 = makeConnection()
        try await connectAndWait(conn2)

        // conn1 should be cancelled by the listener at this point.
        // Verify conn2 can still deliver frames.
        async let firstFrame = listener.frames.first(where: { _ in true })
        try await send(try moveFrame(x: 0.9, y: 0.1, seq: 0), on: conn2)

        let frame = await firstFrame
        XCTAssertNotNil(frame)
        conn1.cancel()
        conn2.cancel()
    }

    // MARK: - A3 Edge cases

    /// Three frames arriving in 5 arbitrary-sized TCP chunks — verifies the drainFrames
    /// state machine correctly reassembles across multiple partial-reads.
    ///
    /// Frame layout:
    ///   frame1: 36 bytes (STYLUS_MOVE)
    ///   frame2: 20 bytes (STYLUS_PROXIMITY)
    ///   frame3: 20 bytes (STYLUS_SCROLL)   → total 76 bytes
    ///
    /// Chunks: 4 + 8 + 12 + 30 + 22 = 76 bytes covering all 3 frames.
    func testThreeFramesInFiveChunksReassemble() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        // Build 3 frames
        let f1 = try BinaryStylusCodec.encode(
            .move(x: 0.1, y: 0.2, pressure: 100, tiltX: 10, tiltY: -10),
            flags: Flags.pressurePresent | Flags.tiltPresent, sequence: 0, timestampNs: 0
        )
        let f2 = try BinaryStylusCodec.encode(
            .proximity(entering: true),
            flags: Flags.hover, sequence: 1, timestampNs: 0
        )
        let f3 = try BinaryStylusCodec.encode(
            .scroll(deltaX: 0, deltaY: 15),
            flags: 0x00, sequence: 2, timestampNs: 0
        )
        // Total: 36 + 20 + 20 = 76 bytes
        var combined = Data()
        combined.append(f1)
        combined.append(f2)
        combined.append(f3)
        XCTAssertEqual(combined.count, 76)

        // Split into 5 chunks: 4 + 8 + 12 + 30 + 22
        let c1 = combined.prefix(4)
        let c2 = combined.dropFirst(4).prefix(8)
        let c3 = combined.dropFirst(12).prefix(12)
        let c4 = combined.dropFirst(24).prefix(30)
        let c5 = combined.dropFirst(54)
        XCTAssertEqual(c1.count + c2.count + c3.count + c4.count + c5.count, 76)

        var received: [DecodedFrame] = []
        let collectTask = Task {
            for await frame in self.listener.frames {
                received.append(frame)
                if received.count == 3 { break }
            }
        }

        try await send(Data(c1), on: conn)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await send(Data(c2), on: conn)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await send(Data(c3), on: conn)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await send(Data(c4), on: conn)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await send(Data(c5), on: conn)

        try await Task.sleep(nanoseconds: 300_000_000)
        collectTask.cancel()
        conn.cancel()

        XCTAssertEqual(received.count, 3, "Must reassemble exactly 3 frames from 5 chunks")
        guard case .move = received[0].event else { return XCTFail("Frame 0 must be MOVE") }
        guard case .proximity = received[1].event else { return XCTFail("Frame 1 must be PROXIMITY") }
        guard case .scroll = received[2].event else { return XCTFail("Frame 2 must be SCROLL") }
    }

    /// Two consecutive frames sent in a single TCP write — listener must emit both.
    func testTwoConsecutiveFramesInSingleWrite() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        var combined = Data()
        combined.append(try moveFrame(x: 0.4, y: 0.6, seq: 0))
        combined.append(try moveFrame(x: 0.6, y: 0.4, seq: 1))

        var received: [DecodedFrame] = []
        let collectTask = Task {
            for await frame in self.listener.frames {
                received.append(frame)
                if received.count == 2 { break }
            }
        }

        try await send(combined, on: conn)
        try await Task.sleep(nanoseconds: 200_000_000)
        collectTask.cancel()
        conn.cancel()

        XCTAssertEqual(received.count, 2, "Single write with two frames must emit both")
    }

    /// Unknown event_type at offset 1: listener yields ProtocolError.unknownType AND
    /// drops the entire buffer (including any valid frames that follow).
    /// This is the documented characterization of the unknown-type discard strategy.
    func testUnknownEventTypeYieldsErrorAndDropsBuffer() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        // 36-byte payload: version=1, event_type=0xAA (unknown), rest zeros.
        // Followed immediately by a valid MOVE frame — the valid frame should be dropped.
        var badFrame = Data(repeating: 0x00, count: 36)
        badFrame[0] = 0x01    // version
        badFrame[1] = 0xAA    // unknown type

        let validFrame = try moveFrame(x: 0.5, y: 0.5, seq: 1)

        var combined = badFrame
        combined.append(validFrame)

        var errors: [Error] = []
        var frames: [DecodedFrame] = []

        let errorTask = Task {
            for await err in self.listener.errors {
                errors.append(err)
                if errors.count >= 1 { break }
            }
        }
        let frameTask = Task {
            for await frame in self.listener.frames {
                frames.append(frame)
            }
        }

        try await send(combined, on: conn)
        try await Task.sleep(nanoseconds: 300_000_000)
        errorTask.cancel()
        frameTask.cancel()
        conn.cancel()

        // At least one unknownType error must have been emitted.
        let hasUnknownTypeError = errors.contains { err in
            if case ProtocolError.unknownType(let got) = err as! ProtocolError, got == 0xAA { return true }
            return false
        }
        XCTAssertTrue(hasUnknownTypeError,
            "Unknown event_type 0xAA must yield ProtocolError.unknownType(got: 0xAA)")

        // The valid frame following the bad one is dropped (characterization — discard strategy).
        XCTAssertEqual(frames.count, 0,
            "Frames after an unknown type in the buffer must be dropped (current discard behaviour)")
    }

    /// Trailing partial frame: listener accumulates it and completes on the next chunk.
    func testTrailingPartialFrameCompletesOnNextChunk() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        let frame = try moveFrame(x: 0.7, y: 0.3, seq: 5)
        // Send only the first 20 bytes (partial — MOVE needs 36).
        let part1 = frame.prefix(20)
        let part2 = frame.dropFirst(20)

        var received: [DecodedFrame] = []
        let collectTask = Task {
            for await f in self.listener.frames {
                received.append(f)
                if received.count >= 1 { break }
            }
        }

        try await send(Data(part1), on: conn)
        try await Task.sleep(nanoseconds: 50_000_000)
        // After first chunk, no frame should have been emitted yet.
        XCTAssertEqual(received.count, 0, "Partial frame must not be emitted before complete")

        try await send(Data(part2), on: conn)
        try await Task.sleep(nanoseconds: 200_000_000)
        collectTask.cancel()
        conn.cancel()

        XCTAssertEqual(received.count, 1, "Frame must be emitted after the second (completing) chunk")
        guard case let .move(rx, ry, _, _, _) = received[0].event else {
            return XCTFail("Expected MOVE event")
        }
        XCTAssertEqual(rx, 0.7, accuracy: 0.001)
        XCTAssertEqual(ry, 0.3, accuracy: 0.001)
    }

    /// Verifies the listener accepts connections with TCP_NODELAY enabled.
    ///
    /// "noDelay works" cannot be tested without a timing harness, but we verify
    /// the listener is still functional end-to-end after the NWParameters change.
    func testNoDelayListenerAcceptsAndDecodesFrame() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let conn = makeConnection()
        try await connectAndWait(conn)

        let data = try moveFrame(x: 0.5, y: 0.5)
        async let firstFrame = listener.frames.first(where: { _ in true })
        try await send(data, on: conn)

        let frame = await firstFrame
        let received = try XCTUnwrap(frame)
        guard case let .move(rx, ry, _, _, _) = received.event else {
            return XCTFail("Expected move event from noDelay listener")
        }
        XCTAssertEqual(rx, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ry, 0.5, accuracy: 0.0001)
        conn.cancel()
    }
}
