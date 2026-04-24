import XCTest
import Network
@testable import InkBridgeCore

/// Tests for ``UDPListener``. Phase 3.4.
///
/// Uses port 45451 (avoids conflicts with 4545) and loopback NWConnection
/// to send datagrams without a real Wi-Fi interface.
final class UDPListenerTests: XCTestCase {

    private static let testPort: UInt16 = 45451
    private var listener: UDPListener!

    override func setUp() {
        super.setUp()
        listener = UDPListener(port: Self.testPort)
    }

    override func tearDown() {
        listener.stop()
        listener = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Sends `data` as a single UDP datagram to 127.0.0.1:testPort.
    private func sendDatagram(_ data: Data) async throws {
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.testPort)!,
            using: .udp
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
                    })
                case .failed(let error):
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Encodes a STYLUS_MOVE frame with given x/y.
    private func moveFrame(x: Float, y: Float, seq: UInt32 = 0) throws -> Data {
        try BinaryStylusCodec.encode(
            .move(x: x, y: y, pressure: 1000, tiltX: 100, tiltY: -50),
            flags: Flags.pressurePresent | Flags.tiltPresent,
            sequence: seq,
            timestampNs: 12345
        )
    }

    // MARK: - Tests

    func testListenerReceivesDecodedFrame() async throws {
        try listener.start()
        // Give the listener a moment to bind.
        try await Task.sleep(nanoseconds: 100_000_000)

        let data = try moveFrame(x: 0.5, y: 0.25)

        async let firstFrame = listener.frames.first(where: { _ in true })
        try await sendDatagram(data)

        let frame = await firstFrame
        let received = try XCTUnwrap(frame)
        guard case let .move(rx, ry, rp, _, _) = received.event else {
            return XCTFail("Expected move event")
        }
        XCTAssertEqual(rx, 0.5, accuracy: 0.0001)
        XCTAssertEqual(ry, 0.25, accuracy: 0.0001)
        XCTAssertEqual(rp, 1000)
    }

    func testCorruptedDataYieldsError() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Build a full 36-byte buffer (MOVE size) with bad version byte 0xFF.
        // A truncated 4-byte payload throws .truncated, not .badVersion — we need
        // at least 16 bytes so the codec reads the version before checking payload.
        var corrupt = Data(repeating: 0x00, count: 36)
        corrupt[0] = 0xFF  // bad version
        corrupt[1] = 0x01  // STYLUS_MOVE (so codec gets past event_type)

        async let firstError = listener.errors.first(where: { _ in true })
        try await sendDatagram(corrupt)

        let err = await firstError
        XCTAssertNotNil(err)
        // Verify it's a protocol error (bad version byte 0xFF).
        XCTAssertEqual(err as? ProtocolError, .badVersion(got: 0xFF))
    }

    func testOutOfOrderDatagramIsDropped() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Send seq=10, seq=12, seq=11 — seq=11 must be dropped.
        let d10 = try moveFrame(x: 0.1, y: 0.1, seq: 10)
        let d12 = try moveFrame(x: 0.2, y: 0.2, seq: 12)
        let d11 = try moveFrame(x: 0.3, y: 0.3, seq: 11)

        var received: [UInt32] = []
        let collectTask = Task {
            for await frame in self.listener.frames {
                received.append(frame.header.sequence)
                if received.count == 2 { break }
            }
        }

        try await sendDatagram(d10)
        try await Task.sleep(nanoseconds: 50_000_000)
        try await sendDatagram(d12)
        try await Task.sleep(nanoseconds: 50_000_000)
        try await sendDatagram(d11)
        try await Task.sleep(nanoseconds: 100_000_000)

        collectTask.cancel()
        // seq 10 and 12 accepted; seq 11 dropped (< last accepted 12).
        XCTAssertTrue(received.contains(10))
        XCTAssertTrue(received.contains(12))
        XCTAssertFalse(received.contains(11))
    }

    /// Regression: a single sender socket must keep delivering datagrams
    /// after the first one. Previously the receive loop exited on
    /// `isComplete=true` which fires after every UDP datagram.
    func testSingleSenderSocketReceivesMultipleDatagrams() async throws {
        try listener.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.testPort)!,
            using: .udp
        )

        // Wait until the sender socket is ready.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let error): cont.resume(throwing: error)
                default: break
                }
            }
            connection.start(queue: .global())
        }

        var received: [UInt32] = []
        let collectTask = Task {
            for await frame in self.listener.frames {
                received.append(frame.header.sequence)
                if received.count >= 5 { break }
            }
        }

        // Send 5 datagrams from the same socket, monotonically increasing sequence.
        for seq in UInt32(1)...UInt32(5) {
            let data = try moveFrame(x: Float(seq) / 10, y: 0.5, seq: seq)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                })
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        collectTask.cancel()
        connection.cancel()

        XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5])
    }
}
