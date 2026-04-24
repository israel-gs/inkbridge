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
