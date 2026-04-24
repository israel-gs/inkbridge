import Foundation
import Network

/// UDP transport listener. Binds to `0.0.0.0:port` so it accepts datagrams
/// from Wi-Fi clients on any interface. transport.md R3.
///
/// Each UDP "connection" (NWListener creates one per sender address) calls
/// `receiveMessage` in a loop. Decoded frames are yielded to ``frames``;
/// decode failures are yielded to ``errors``.
///
/// Out-of-order sequence dropping (wire-protocol.md R9) is performed here.
public final class UDPListener: PacketListener {

    // MARK: - Public AsyncStreams

    public let frames: AsyncStream<DecodedFrame>
    public let errors: AsyncStream<Error>

    // MARK: - Private

    private let port: UInt16
    private let codec: BinaryStylusCodec
    private var listener: NWListener?
    private let frameContinuation: AsyncStream<DecodedFrame>.Continuation
    private let errorContinuation: AsyncStream<Error>.Continuation

    /// Last accepted sequence number per remote endpoint (keyed by description string).
    /// Protects against out-of-order datagrams per wire-protocol.md R9.
    private var lastSequence: [String: UInt32] = [:]

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
        let params = NWParameters.udp
        // Bind to all interfaces so Wi-Fi clients can reach us. transport.md R3.
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ListenerError.invalidPort(port)
        }

        let l = try NWListener(using: params, on: nwPort)
        self.listener = l

        l.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
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
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInteractive))
        receiveLoop(connection: connection)
    }

    private func receiveLoop(connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                self.errorContinuation.yield(error)
            }

            if let data, !data.isEmpty {
                self.processData(data, from: connection)
            }

            // For UDP datagrams, `isComplete` is true after every message
            // because each datagram is a complete message on its own — it does
            // NOT mean the connection is torn down. Always loop unless the
            // connection itself is cancelled / failed.
            switch connection.state {
            case .cancelled, .failed:
                return
            default:
                self.receiveLoop(connection: connection)
            }
        }
    }

    private func processData(_ data: Data, from connection: NWConnection) {
        do {
            let frame = try BinaryStylusCodec.decode(data)
            let endpointKey = "\(connection.endpoint)"

            // Out-of-order drop per wire-protocol.md R9.
            if let last = lastSequence[endpointKey] {
                let seq = frame.header.sequence
                // Handle sequence wrap (R9 scenario): treat 0 after 0xFFFFFFFF as valid.
                if last != UInt32.max, seq < last {
                    // Stale — discard silently.
                    return
                }
            }
            lastSequence[endpointKey] = frame.header.sequence
            frameContinuation.yield(frame)
        } catch {
            errorContinuation.yield(error)
        }
    }
}

/// Errors thrown by transport listeners.
public enum ListenerError: Error {
    case invalidPort(UInt16)
}
