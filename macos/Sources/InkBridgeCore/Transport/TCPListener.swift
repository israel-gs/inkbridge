import Foundation
import Network

/// TCP transport listener. Binds to `127.0.0.1:port` (loopback only) for the
/// `adb reverse` USB path. transport.md R4.
///
/// TCP is a stream protocol so frames must be reassembled from the byte stream.
/// This implementation uses a per-connection buffer state machine:
///   1. Accumulate bytes in `buffer`.
///   2. Once ≥ 16 bytes, parse the fixed header.
///   3. Derive payload size from `event_type` (MOVE=20, PROX/BUTTON=4).
///   4. Once ≥ header+payload bytes, emit the frame and advance the buffer.
///
/// At most one client is accepted at a time; a new connection replaces the
/// existing one. transport.md R4.
public final class TCPListener: PacketListener {

    // MARK: - Public AsyncStreams

    public let frames: AsyncStream<DecodedFrame>
    public let errors: AsyncStream<Error>

    // MARK: - Private

    private let port: UInt16
    private let codec: BinaryStylusCodec
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let frameContinuation: AsyncStream<DecodedFrame>.Continuation
    private let errorContinuation: AsyncStream<Error>.Continuation

    // MARK: - Init

    public init(port: UInt16, codec: BinaryStylusCodec = BinaryStylusCodec()) {
        self.port = port
        self.codec = codec

        var fc: AsyncStream<DecodedFrame>.Continuation!
        var ec: AsyncStream<Error>.Continuation!

        self.frames = AsyncStream<DecodedFrame> { continuation in
            fc = continuation
        }
        self.errors = AsyncStream<Error> { continuation in
            ec = continuation
        }

        self.frameContinuation = fc
        self.errorContinuation = ec
    }

    deinit {
        stop()
    }

    // MARK: - PacketListener

    public func start() throws {
        let params = NWParameters.tcp
        // Bind to loopback only — only meaningful with `adb reverse`. transport.md R4.
        // Setting requiredLocalEndpoint pins the listener to 127.0.0.1 and the desired
        // port. We must NOT pass the port again in NWListener(using:on:) — that causes
        // EINVAL (duplicate port specification). Use port 0 in the constructor and let
        // the endpoint carry the real port.
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.invalidPort(port)
        }
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)

        let l = try NWListener(using: params, on: .any)
        self.listener = l

        l.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.errorContinuation.yield(error)
            case .cancelled:
                self?.frameContinuation.finish()
                self?.errorContinuation.finish()
            default:
                break
            }
        }

        l.start(queue: .global(qos: .userInteractive))
    }

    public func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleNewConnection(_ connection: NWConnection) {
        // Replace existing connection. transport.md R4.
        activeConnection?.cancel()
        activeConnection = connection
        connection.start(queue: .global(qos: .userInteractive))

        var buffer = Data()
        receiveBytes(connection: connection, buffer: &buffer)
    }

    private func receiveBytes(connection: NWConnection, buffer: inout Data) {
        // Capture buffer by value into the closure; update it on each receive.
        var localBuffer = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                self.errorContinuation.yield(error)
            }

            if let data, !data.isEmpty {
                localBuffer.append(data)
                self.drainFrames(from: &localBuffer)
            }

            if isComplete {
                // Client closed — return to listening. transport.md R4.
                if self.activeConnection === connection {
                    self.activeConnection = nil
                }
                return
            }

            if error == nil {
                self.receiveBytes(connection: connection, buffer: &localBuffer)
            }
        }
    }

    // MARK: - Frame extraction state machine

    private static let headerSize = 16

    private func drainFrames(from buffer: inout Data) {
        while true {
            // Need at least a header.
            guard buffer.count >= Self.headerSize else { break }

            // Peek at event_type byte (offset 1) to get payload size.
            let eventType = buffer[buffer.startIndex + 1]
            let payloadSize: Int
            switch eventType {
            case 0x01: payloadSize = 20   // STYLUS_MOVE
            case 0x02: payloadSize = 4    // STYLUS_PROXIMITY
            case 0x03: payloadSize = 4    // STYLUS_BUTTON
            default:
                // Unknown type — cannot determine payload size. Discard entire buffer.
                errorContinuation.yield(ProtocolError.unknownType(got: eventType))
                buffer.removeAll()
                return
            }

            let frameSize = Self.headerSize + payloadSize
            guard buffer.count >= frameSize else { break }

            let frameData = buffer.prefix(frameSize)
            buffer.removeFirst(frameSize)

            do {
                let frame = try BinaryStylusCodec.decode(frameData)
                frameContinuation.yield(frame)
            } catch {
                errorContinuation.yield(error)
            }
        }
    }
}
