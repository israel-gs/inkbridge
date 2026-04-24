import Foundation
import Combine
import CoreGraphics

/// The InkBridge macOS server.
///
/// Wires ``UDPListener`` + ``TCPListener`` + ``CoordinateMapper`` + ``Injector``.
/// Exposes ``state`` and ``stats`` via Combine ``@Published`` properties so
/// the SwiftUI ViewModel can observe changes on the main thread.
///
/// Access pattern: instantiate with concrete listeners and an injector,
/// call ``start()`` to begin listening.
@MainActor
public final class InkBridgeServer: ObservableObject {

    // MARK: - Public published state

    @Published public private(set) var state: ServerState = .idle
    @Published public private(set) var stats: Stats = Stats()

    // MARK: - Dependencies

    private let udpListener: PacketListener
    private let tcpListener: PacketListener
    private let injector: Injector

    /// The display rect used for coordinate mapping. Refreshed externally when
    /// the display configuration changes. macos-injection.md R5.
    public var displayRect: DisplayRect

    // MARK: - Internal tasks

    private var udpTask: Task<Void, Never>?
    private var tcpTask: Task<Void, Never>?
    private var udpErrorTask: Task<Void, Never>?
    private var tcpErrorTask: Task<Void, Never>?

    /// Last known stylus position, updated by every MOVE frame.
    /// Used as the fallback coordinate for BUTTON and PROXIMITY events, whose
    /// wire payloads carry no x/y. Defaults to display center until the first MOVE.
    private var lastPoint: CGPoint

    // MARK: - Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - port: The port both listeners will bind to (default 4545).
    ///   - injector: The ``Injector`` to use. Pass ``MockInjector`` in tests.
    ///   - udpListener: Override for testing. Default creates a ``UDPListener``.
    ///   - tcpListener: Override for testing. Default creates a ``TCPListener``.
    ///   - displayRect: Initial display size. Defaults to main display bounds.
    public init(
        port: UInt16 = 4545,
        injector: Injector,
        udpListener: PacketListener? = nil,
        tcpListener: PacketListener? = nil,
        displayRect: DisplayRect? = nil
    ) {
        self.injector = injector
        self.udpListener = udpListener ?? UDPListener(port: port)
        self.tcpListener = tcpListener ?? TCPListener(port: port)

        let resolvedRect: DisplayRect
        if let rect = displayRect {
            resolvedRect = rect
        } else {
            let mainID = CGMainDisplayID()
            let bounds = CGDisplayBounds(mainID)
            resolvedRect = DisplayRect(width: bounds.width, height: bounds.height)
        }
        self.displayRect = resolvedRect
        self.lastPoint = CGPoint(x: resolvedRect.width / 2, y: resolvedRect.height / 2)
    }

    // MARK: - Lifecycle

    /// Bind both listeners and start processing frames.
    public func start(port: UInt16 = 4545) {
        do {
            try udpListener.start()
            try tcpListener.start()
            state = .listening(port: port)
        } catch {
            state = .degraded(reason: error.localizedDescription)
            return
        }

        let udpFrames = udpListener.frames
        let tcpFrames = tcpListener.frames
        let udpErrors = udpListener.errors
        let tcpErrors = tcpListener.errors

        udpTask = Task { [weak self] in
            for await frame in udpFrames {
                guard let self else { return }
                await MainActor.run { self.processFrame(frame) }
            }
        }

        tcpTask = Task { [weak self] in
            for await frame in tcpFrames {
                guard let self else { return }
                await MainActor.run { self.processFrame(frame) }
            }
        }

        udpErrorTask = Task { [weak self] in
            for await _ in udpErrors {
                guard let self else { return }
                await MainActor.run { self.stats.packetsDropped += 1 }
            }
        }

        tcpErrorTask = Task { [weak self] in
            for await _ in tcpErrors {
                guard let self else { return }
                await MainActor.run { self.stats.packetsDropped += 1 }
            }
        }
    }

    /// Stop both listeners and cancel all tasks.
    public func stop() {
        udpListener.stop()
        tcpListener.stop()
        udpTask?.cancel()
        tcpTask?.cancel()
        udpErrorTask?.cancel()
        tcpErrorTask?.cancel()
        udpTask = nil
        tcpTask = nil
        udpErrorTask = nil
        tcpErrorTask = nil
        state = .idle
    }

    // MARK: - Frame processing

    private func processFrame(_ frame: DecodedFrame) {
        stats.packetsReceived += 1
        stats.lastPacketAt = Date()

        let event = frame.event
        // MOVE frames carry coordinates; BUTTON and PROXIMITY reuse the last known
        // position so a click lands where the stylus currently is, not at (0,0).
        let point: CGPoint
        if case let .move(x, y, _, _, _) = event {
            let sample = makeSample(frame: frame, x: x, y: y)
            point = CoordinateMapper.map(sample: sample, display: displayRect)
            lastPoint = point
        } else {
            point = lastPoint
        }

        do {
            try injector.inject(event, at: point)
        } catch InjectorError.notTrusted {
            // Surface permission issue upward.
            state = .degraded(reason: "Accessibility permission required")
        } catch {
            // R8: single injection failure must not change server state.
            stats.packetsDropped += 1
        }
    }

    private func makeSample(frame: DecodedFrame, x: Float, y: Float) -> StylusSample {
        let flags = frame.header.flags
        let hover = (flags & Flags.hover) != 0
        // Sample creation can fail if x/y are out of range. Clamp defensively.
        let clampedX = min(max(x, 0), 1)
        let clampedY = min(max(y, 0), 1)
        return (try? StylusSample(
            x: clampedX,
            y: clampedY,
            pressure: 0,
            tiltX: 0,
            tiltY: 0,
            hover: hover,
            timestampNs: frame.header.timestampNs
        )) ?? StylusSample._zero
    }
}

// Convenience to avoid force-try in production code.
private extension StylusSample {
    static let _zero: StylusSample = {
        // swiftlint:disable:next force_try
        try! StylusSample(x: 0, y: 0, pressure: 0, tiltX: 0, tiltY: 0, hover: false, timestampNs: 0)
    }()
}
