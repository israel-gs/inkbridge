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
    @Published public private(set) var latency: LatencyTracker.Snapshot = .zero

    // MARK: - Private latency tracker

    private var latencyTracker = LatencyTracker()

    // MARK: - Smoothing

    /// Per-axis One-Euro filters applied to STYLUS_MOVE coordinates before
    /// `CoordinateMapper`. Off by default at process start; flipped on by the
    /// ViewModel after reading user preferences.
    private var filterX = OneEuroFilter()
    private var filterY = OneEuroFilter()
    /// When false, MOVE frames bypass the filters entirely — no allocation,
    /// no ns-conversion, no syscall. Toggle via `setSmoothingEnabled`.
    private var smoothingEnabled: Bool = true
    /// Throttle `latency` snapshot publishing. snapshot() sorts the whole ring
    /// buffer, and @Published triggers SwiftUI updates — doing this on every
    /// frame at 240 Hz chews MainActor time and kills the injection hot path.
    /// Publish at most ~10 Hz.
    private var lastLatencyPublishNs: UInt64 = 0
    private static let latencyPublishIntervalNs: UInt64 = 100_000_000  // 100 ms

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

        // Bug 6 fix: use @MainActor Task closure instead of Task + inner
        // MainActor.run. The class is @MainActor so `self` is already isolated
        // to the main actor; a nested MainActor.run adds an unnecessary hop that
        // pays a lock-acquisition cost on every frame at 240 Hz.
        udpTask = Task { @MainActor [weak self] in
            for await frame in udpFrames {
                self?.processFrame(frame)
            }
        }

        tcpTask = Task { @MainActor [weak self] in
            for await frame in tcpFrames {
                self?.processFrame(frame)
            }
        }

        // Listener errors (decode failures, NW transport errors) → packetsDropped.
        udpErrorTask = Task { @MainActor [weak self] in
            for await _ in udpErrors {
                self?.stats.packetsDropped += 1
            }
        }

        tcpErrorTask = Task { @MainActor [weak self] in
            for await _ in tcpErrors {
                self?.stats.packetsDropped += 1
            }
        }
    }

    /// Toggle position smoothing on or off. When transitioning from off to on
    /// the filters MUST be reset so the next stroke does not start lagging
    /// against stale velocity estimates.
    public func setSmoothingEnabled(_ enabled: Bool) {
        if enabled && !smoothingEnabled {
            filterX.reset()
            filterY.reset()
        }
        smoothingEnabled = enabled
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
        // Capture arrival timestamp immediately — before any processing overhead.
        let arrivalNs = DispatchTime.now().uptimeNanoseconds

        stats.packetsReceived += 1
        stats.lastPacketAt = Date()

        let event = frame.event

        // Gesture events (scroll/zoom) do NOT update lastPoint — they are directionless
        // and carry no coordinate. Route them directly to the injector and skip
        // the coordinate-mapping path entirely.
        switch event {
        case let .scroll(deltaX, deltaY):
            // Extract phase flags (bits 0x40 BEGIN, 0x80 END) from header.flags.
            let phaseFlags: UInt8 = frame.header.flags & 0xC0
            do {
                try injector.injectScroll(deltaX: deltaX, deltaY: deltaY, phaseFlags: phaseFlags)
            } catch InjectorError.notTrusted {
                state = .degraded(reason: "Accessibility permission required")
            } catch {
                // Injection failure — the frame was decoded correctly but the OS
                // rejected the event. Count separately from listener/decode errors.
                stats.injectionFailures += 1
            }
            recordLatency(arrivalNs: arrivalNs, wireNs: frame.header.timestampNs)
            return

        case let .zoom(scaleDelta):
            do {
                try injector.injectZoom(scaleDelta: scaleDelta)
            } catch InjectorError.notTrusted {
                state = .degraded(reason: "Accessibility permission required")
            } catch {
                stats.injectionFailures += 1
            }
            recordLatency(arrivalNs: arrivalNs, wireNs: frame.header.timestampNs)
            return

        case let .key(keyCode, modifiers, action):
            do {
                try injector.injectKey(keyCode: keyCode, modifiers: modifiers, action: action)
            } catch InjectorError.notTrusted {
                state = .degraded(reason: "Accessibility permission required")
            } catch {
                stats.injectionFailures += 1
            }
            recordLatency(arrivalNs: arrivalNs, wireNs: frame.header.timestampNs)
            return

        case let .cursorDelta(deltaX, deltaY):
            do {
                try injector.injectCursorDelta(deltaX: deltaX, deltaY: deltaY)
            } catch InjectorError.notTrusted {
                state = .degraded(reason: "Accessibility permission required")
            } catch {
                stats.injectionFailures += 1
            }
            // Sync the server's lastPoint with the system cursor so a follow-up
            // BUTTON frame (tap = click) lands where the cursor actually is,
            // not at the stale lastPoint from the previous stylus session.
            if let probe = CGEvent(source: nil) {
                lastPoint = probe.location
            }
            recordLatency(arrivalNs: arrivalNs, wireNs: frame.header.timestampNs)
            return

        default:
            break
        }

        // PROXIMITY entering=true resets the smoothing filters so a fresh
        // stylus session starts without lag from the previous one.
        if case let .proximity(entering) = event, entering {
            filterX.reset()
            filterY.reset()
        }

        // MOVE frames carry coordinates; BUTTON and PROXIMITY reuse the last known
        // position so a click lands where the stylus currently is, not at (0,0).
        let point: CGPoint
        if case let .move(rawX, rawY, _, _, _) = event {
            let (sx, sy): (Float, Float) = smoothingEnabled
                ? (filterX.filter(rawX, timestampNs: arrivalNs),
                   filterY.filter(rawY, timestampNs: arrivalNs))
                : (rawX, rawY)
            let sample = makeSample(frame: frame, x: sx, y: sy)
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
            // Count as injectionFailures (OS rejection), not packetsDropped (decode error).
            stats.injectionFailures += 1
        }

        recordLatency(arrivalNs: arrivalNs, wireNs: frame.header.timestampNs)
    }

    private func recordLatency(arrivalNs: UInt64, wireNs: UInt64) {
        // Record latency after inject returns. wireNs comes from the packet header
        // (Android System.nanoTime() — different clock domain; see LatencyTracker docs).
        let injectNs = DispatchTime.now().uptimeNanoseconds
        latencyTracker.record(
            wireNs: wireNs,
            arrivalNs: arrivalNs,
            injectNs: injectNs
        )
        // Throttled publish — sorting+Combine on every frame stalls the
        // injection hot path under 240 Hz stylus sampling.
        if injectNs - lastLatencyPublishNs >= Self.latencyPublishIntervalNs {
            lastLatencyPublishNs = injectNs
            latency = latencyTracker.snapshot()
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
