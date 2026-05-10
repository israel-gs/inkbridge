import Foundation
import Observation
import CoreGraphics
import QuartzCore
import SwiftUI

// MARK: - ClickFlashState

/// Momentary visual indicator for stylus button clicks on the canvas.
///
/// Emitted by `CaptureViewModel.clickFlash` for 80 ms after a button event fires.
public enum ClickFlashState: Equatable {
    /// No active click flash.
    case idle
    /// Left-click (primary button) flash at the given canvas location.
    case left(at: CGPoint)
    /// Right-click (secondary button) flash at the given canvas location.
    case right(at: CGPoint)

    public static func == (lhs: ClickFlashState, rhs: ClickFlashState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.left(let a), .left(let b)): return a == b
        case (.right(let a), .right(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - CaptureViewModel

/// Concrete view model for the capture screen.
///
/// Conforms to `TouchEventSink` (receives batched samples from `CanvasUIView`) and
/// drives the capture canvas UI. Replaces the `CaptureScreenViewModelProtocol`
/// forward declaration from Batch 5 (`CaptureScreen.swift`).
///
/// # Responsibilities
/// - Routes touch samples through `TouchRouter` → `[StylusEvent]`.
/// - Encodes each event via `BinaryStylusCodec` and sends via `UDPClient`.
/// - Handles Express Key events from `ExpressKeysSidebar`.
/// - Mirrors `ConnectionState` from the associated `ConnectionViewModel`.
/// - Exposes `activeProfile` for the sidebar.
///
/// # Main-actor isolation
/// All property mutations are `@MainActor`. Send calls are dispatched via
/// non-awaited `Task` to avoid blocking the touch callback thread.
@Observable
@MainActor
public final class CaptureViewModel: TouchEventSink {

    // MARK: - Observed properties (used by CaptureScreen)

    /// Current connection state, mirrored from `ConnectionViewModel`.
    public private(set) var connectionState: ConnectionState

    /// The active Express Key profile, driving the sidebar labels.
    public private(set) var activeProfile: ExpressKeyProfile

    /// Which edge the Express Key sidebar appears on.
    public var sidebarEdge: SidebarEdge = .trailing

    /// Brief visual indicator when a stylus button event fires. Resets to `.idle` after 80 ms.
    public private(set) var clickFlash: ClickFlashState = .idle

    // MARK: - Dependencies

    private let udpClient: any UDPClient
    private let sequenceCounter: SequenceCounter
    private var touchRouter: TouchRouter
    private let settingsRepo: any SettingsRepository

    // MARK: - Internal flash state

    /// Location of the last processed touch sample — used to position the click flash.
    private var lastSampleLocation: CGPoint = .zero

    // MARK: - Init

    public init(
        udpClient: any UDPClient,
        settingsRepo: any SettingsRepository,
        connectionState: ConnectionState = .idle,
        activeProfile: ExpressKeyProfile = .makeDefault(),
        sequenceCounter: SequenceCounter = SequenceCounter()
    ) {
        self.udpClient = udpClient
        self.settingsRepo = settingsRepo
        self.connectionState = connectionState
        self.activeProfile = activeProfile
        self.sequenceCounter = sequenceCounter
        self.touchRouter = TouchRouter(now: { CACurrentMediaTime() })
    }

    // MARK: - TouchEventSink conformance

    /// Receives batched touch samples from `CanvasUIView` and sends encoded events.
    ///
    /// Bug 2 fix: calls the batch API `process(samples:phase:)` once per UIKit callback
    /// instead of looping over samples. This guarantees at most ONE scroll/zoom event per
    /// ingest call for 2-finger steady-state moves, eliminating doubled event rate on Mac.
    public func ingest(_ samples: [TouchSample], phase: TouchPhase) {
        print("[CaptureViewModel] ingest phase=\(phase) samples=\(samples.count)")
        // Track the location of the last sample for click-flash positioning.
        if let last = samples.last { lastSampleLocation = last.location }

        let events = touchRouter.process(samples: samples, phase: phase)
        if !events.isEmpty {
            print("[CaptureViewModel] router emitted \(events)")
        }
        // Use the last sample location for flash positioning (best approximation
        // when multiple samples arrive in one batch).
        let flashLocation = samples.last?.location ?? lastSampleLocation
        for event in events {
            sendEvent(event)
            triggerClickFlashIfNeeded(for: event, at: flashLocation)
        }
    }

    // MARK: - Express Key handling

    /// Handles an Express Key event from the sidebar.
    /// - Parameter event: A `StylusEvent` produced by `ExpressKeyDispatcher`.
    public func handleExpressKeyEvent(_ event: StylusEvent) {
        sendEvent(event)
    }

    // MARK: - Connection management

    /// Disconnects from the server and resets state.
    public func disconnect() {
        connectionState = .idle
        Task { await udpClient.disconnect() }
    }

    /// Updates the mirrored connection state. Called by `ConnectionViewModel`
    /// when the transport state changes.
    public func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    /// Updates the active profile (e.g. user switched profiles in settings).
    public func updateActiveProfile(_ profile: ExpressKeyProfile) {
        activeProfile = profile
    }

    // MARK: - Private

    /// Triggers a brief 80 ms click flash overlay when a stylus button DOWN event fires.
    ///
    /// Wire-format button bits (per protocol §Flags):
    ///   bit 3 (0x08) = BUTTON_PRIMARY pressed → left click flash
    ///   bit 4 (0x10) = BUTTON_SECONDARY pressed → right click flash
    ///   0x00         = all released → no flash
    private func triggerClickFlashIfNeeded(for event: StylusEvent, at location: CGPoint) {
        guard case .stylusButton(let buttons, let primaryDown) = event else { return }
        // Only flash on button-down events, not button-up (buttons == 0x00).
        let isPrimaryDown   = (buttons & 0x08) != 0   // BUTTON_PRIMARY (bit 3)
        let isSecondaryDown = (buttons & 0x10) != 0   // BUTTON_SECONDARY (bit 4)
        guard isPrimaryDown || isSecondaryDown else { return }
        _ = primaryDown  // suppress unused-variable warning; `buttons` carries the authoritative state

        let flash: ClickFlashState = isPrimaryDown ? .left(at: location) : .right(at: location)
        clickFlash = flash

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000) // 80 ms
            self?.clickFlash = .idle
        }
    }

    /// Applies natural-scroll inversion to a scroll event when the setting is enabled.
    ///
    /// Natural scrolling (default: on) matches macOS Sequoia's trackpad default: content
    /// moves WITH the fingers, which means deltaY is inverted relative to the raw
    /// centroid-down direction. The Mac server and codec are unaware of this preference —
    /// inversion is a client-side presentation concern applied BEFORE encoding.
    private func applyNaturalScroll(_ event: StylusEvent) -> StylusEvent {
        guard case .stylusScroll(let dx, let dy, let phase) = event else { return event }
        if settingsRepo.naturalScroll {
            return .stylusScroll(deltaX: -dx, deltaY: -dy, phase: phase)
        }
        return event
    }

    /// Encodes a `StylusEvent` and sends it via the UDP client.
    /// Fire-and-forget — send errors are silently dropped (latency > reliability).
    private func sendEvent(_ event: StylusEvent) {
        // Apply natural-scroll inversion before encoding so the Mac receives
        // the already-inverted deltas. The codec and wire format are unchanged.
        let outEvent = applyNaturalScroll(event)
        Task { [weak self, outEvent] in
            guard let self else { return }
            let seq = await sequenceCounter.next()
            let ts = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
            let flags: UInt8 = flagsFor(outEvent)
            let data = BinaryStylusCodec.encode(outEvent, flags: flags, sequence: seq, timestampNs: ts)
            do {
                try await udpClient.send(data)
                // Diagnostic: confirm packet leaves the device.
                print("[CaptureViewModel] sent event=\(outEvent) bytes=\(data.count)")
            } catch {
                print("[CaptureViewModel] send error: \(error)")
            }
        }
    }

    /// Derives the `flags` byte for the given event.
    ///
    /// Per wire protocol §Flags (README.md):
    ///   bits 3–4 (0x18) = BUTTON_PRIMARY / BUTTON_SECONDARY for STYLUS_BUTTON events.
    ///   bit  6   (0x40) = SCROLL_BEGIN / ZOOM_BEGIN — phase == 0
    ///   bit  7   (0x80) = SCROLL_END   / ZOOM_END   — phase == 2
    ///   both 6+7 clear  = SCROLL_CHANGED / ZOOM_CHANGED — phase == 1
    ///
    /// macOS CGEventInjector.injectScroll decodes:
    ///   0x40 → kCGScrollPhaseBegan (1)
    ///   0x80 → kCGScrollPhaseEnded (4)
    ///   0x00 → kCGScrollPhaseChanged (2)
    ///
    /// R8 consistency rule: the macOS decoder discards any STYLUS_BUTTON frame where
    /// `buttons != (flags & 0x18)`. This method guarantees consistency by deriving
    /// flags directly from the `buttons` bitmask in the event.
    ///
    /// Note: injectZoom on the Mac side uses a Cmd+scroll fallback that does not
    /// read phase flags — zoom phase encoding is included here for protocol
    /// correctness and future compatibility if the gesture-event path is re-enabled.
    private func flagsFor(_ event: StylusEvent) -> UInt8 {
        switch event {
        case .stylusButton(let buttons, _):
            // Mask to bits 3–4 only (0x18). The buttons field already carries these
            // wire-format bits — no translation needed.
            return buttons & 0x18

        case .stylusScroll(_, _, let phase):
            // Encode scroll phase into bits 6–7.
            // phase 0 = begin  → 0x40
            // phase 2 = ended  → 0x80
            // phase 1 = changed → 0x00
            switch phase {
            case 0: return 0x40
            case 2: return 0x80
            default: return 0x00
            }

        case .stylusZoom(_, let phase):
            // Encode zoom phase into bits 6–7 using the same bit positions as scroll.
            // The Mac injectZoom currently uses Cmd+scroll fallback and does not read
            // phase flags, but we encode them correctly for protocol consistency.
            switch phase {
            case 0: return 0x40
            case 2: return 0x80
            default: return 0x00
            }

        default:
            return 0x00
        }
    }
}
