import XCTest
@testable import InkBridgeCore

@MainActor
final class InjectKeyServerRoutingTests: XCTestCase {

    private var udpListener: NoOpListener!
    private var tcpListener: NoOpListener!
    private var injector: MockInjector!
    private var server: InkBridgeServer!

    override func setUp() async throws {
        udpListener = NoOpListener()
        tcpListener = NoOpListener()
        injector = MockInjector()
        server = InkBridgeServer(
            injector: injector,
            udpListener: udpListener,
            tcpListener: tcpListener,
            displayRect: DisplayRect(width: 1920, height: 1080)
        )
    }

    override func tearDown() async throws {
        server.stop()
    }

    func test_keyTapFrameCallsInjectKey() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        let event: StylusEvent = .key(keyCode: 0x06, modifiers: 0x01, action: .tap)
        let data = try BinaryStylusCodec.encode(event, flags: 0, sequence: 1, timestampNs: 0)
        let frame = try BinaryStylusCodec.decode(data)
        udpListener.emit(frame)

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(injector.keyCalls.count, 1)
        XCTAssertEqual(injector.keyCalls.first?.0, 0x06)
        XCTAssertEqual(injector.keyCalls.first?.1, 0x01)
        XCTAssertEqual(injector.keyCalls.first?.2, .tap)

        // Key events do NOT route through inject() (the stylus path).
        XCTAssertTrue(injector.calls.isEmpty)
    }

    func test_keyEventDoesNotUpdateLastPoint() async throws {
        server.start(port: 4545)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Move first to set lastPoint.
        let move = try BinaryStylusCodec.decode(
            try BinaryStylusCodec.encode(
                .move(x: 0.5, y: 0.5, pressure: 0, tiltX: 0, tiltY: 0),
                flags: 0, sequence: 1, timestampNs: 0
            )
        )
        udpListener.emit(move)
        try await Task.sleep(nanoseconds: 30_000_000)

        // Key event should not update lastPoint or call inject().
        let key = try BinaryStylusCodec.decode(
            try BinaryStylusCodec.encode(
                .key(keyCode: 0x00, modifiers: 0x02, action: .press),
                flags: 0, sequence: 2, timestampNs: 0
            )
        )
        udpListener.emit(key)
        try await Task.sleep(nanoseconds: 30_000_000)

        // Now a button event — should land at the previous move point, not (0,0).
        let button = try BinaryStylusCodec.decode(
            try BinaryStylusCodec.encode(
                .button(buttons: 0x08),
                flags: 0x08, sequence: 3, timestampNs: 0
            )
        )
        udpListener.emit(button)
        try await Task.sleep(nanoseconds: 50_000_000)

        // The button call's point must equal the move's resolved point (960, 540).
        let buttonCall = injector.calls.first(where: { call in
            if case .button = call.0 { return true } else { return false }
        })
        XCTAssertNotNil(buttonCall)
        XCTAssertEqual(buttonCall!.1.x, 960, accuracy: 1)
        XCTAssertEqual(buttonCall!.1.y, 540, accuracy: 1)
    }
}
