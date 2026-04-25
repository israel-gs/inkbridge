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
    //
    // Recreated per `start()` session — AsyncStream is single-iterator and the
    // server's consumer Task is cancelled in stop(). See UDPListener for the
    // full rationale.
    public private(set) var frames: AsyncStream<DecodedFrame> = AsyncStream { _ in }
    public private(set) var errors: AsyncStream<Error> = AsyncStream { _ in }

    // MARK: - Private

    private let port: UInt16
    private let codec: BinaryStylusCodec
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var frameContinuation: AsyncStream<DecodedFrame>.Continuation?
    private var errorContinuation: AsyncStream<Error>.Continuation?

    // MARK: - Init

    public init(port: UInt16, codec: BinaryStylusCodec = BinaryStylusCodec()) {
        self.port = port
        self.codec = codec
        recreateStreams()
    }

    deinit {
        stop()
    }

    private func recreateStreams() {
        var fc: AsyncStream<DecodedFrame>.Continuation!
        var ec: AsyncStream<Error>.Continuation!
        self.frames = AsyncStream<DecodedFrame> { continuation in fc = continuation }
        self.errors = AsyncStream<Error> { continuation in ec = continuation }
        self.frameContinuation = fc
        self.errorContinuation = ec
    }

    // MARK: - PacketListener

    public func start() throws {
        // Fresh streams for this session.
        recreateStreams()

        // Disable Nagle's algorithm so small stylus packets are sent immediately
        // rather than being buffered for up to ~200ms by the kernel. Without this,
        // the 20–36 byte frames are coalesced, adding significant draw latency.
        // transport.md R4.
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

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
                self?.errorContinuation?.yield(error)
            case .cancelled:
                break
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
        // Terminate this session's streams so the server's for-await exits.
        // start() will spin up fresh streams.
        frameContinuation?.finish()
        errorContinuation?.finish()
        frameContinuation = nil
        errorContinuation = nil
    }

    /// Sends a wire-format frame back to the currently-connected client.
    /// Used for Mac → tablet messages such as CAPTURE_RESPONSE. No-op when
    /// no client is connected. Errors are forwarded to the errors stream.
    public func send(_ data: Data) {
        guard let connection = activeConnection else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.errorContinuation?.yield(error)
            }
        })
    }

    // MARK: - Connection handling

    private func handleNewConnection(_ connection: NWConnection) {
        // Replace existing connection. transport.md R4.
        activeConnection?.cancel()
        activeConnection = connection

        // Bug 3 (macOS fix): subscribe to the per-connection state so that a
        // mid-session TCP drop (cable unplug, server crash) surfaces via the
        // errors stream. Without this, the only signal was the receive callback
        // error which may not arrive until the next attempted read. The
        // stateUpdateHandler fires as soon as NW detects the broken connection.
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                self.errorContinuation?.yield(error)
                if self.activeConnection === connection {
                    self.activeConnection = nil
                }
            case .cancelled:
                if self.activeConnection === connection {
                    self.activeConnection = nil
                }
            default:
                break
            }
        }

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
                self.errorContinuation?.yield(error)
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
            case 0x04: payloadSize = 4    // STYLUS_SCROLL (R12)
            case 0x05: payloadSize = 4    // STYLUS_ZOOM (R13)
            case 0x06: payloadSize = 4    // CURSOR_DELTA
            case 0x07: payloadSize = 4    // KEY_EVENT (express keys)
            case 0x08: payloadSize = 4    // CAPTURE_REQUEST  (tablet → Mac)
            case 0x09: payloadSize = 4    // CAPTURE_RESPONSE (Mac → tablet, normally outbound)
            default:
                // Unknown type — cannot determine payload size, so the entire buffer
                // must be discarded. This is a known limitation: without a
                // magic-byte sentinel or a u16 length-prefix in the wire protocol,
                // there is no safe way to resync the TCP stream after an unknown
                // event_type. The discard strategy means any trailing valid frames
                // in the same buffer are also lost.
                //
                // TODO(R12-R14): add a framing sentinel or length-prefix to the
                // wire protocol so the receiver can skip unknown frames instead
                // of discarding the entire buffer. See transport.md R12–R14 for
                // the planned protocol revision.
                errorContinuation?.yield(ProtocolError.unknownType(got: eventType))
                buffer.removeAll()
                return
            }

            let frameSize = Self.headerSize + payloadSize
            guard buffer.count >= frameSize else { break }

            let frameData = buffer.prefix(frameSize)
            buffer.removeFirst(frameSize)

            do {
                let frame = try BinaryStylusCodec.decode(frameData)
                frameContinuation?.yield(frame)
            } catch {
                errorContinuation?.yield(error)
            }
        }
    }
}
