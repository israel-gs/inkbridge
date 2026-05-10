import UIKit
import CoreGraphics
import Foundation

// MARK: - MultiTouchPassthroughRecognizer

/// A transparent gesture recognizer that forces all ancestor UIGestureRecognizers
/// (including those inserted by SwiftUI) to allow simultaneous recognition with the
/// canvas touch delivery system.
///
/// Without this, SwiftUI's implicit gesture recognizers (UIPanGestureRecognizer,
/// UITapGestureRecognizer, etc.) can absorb the SECOND touch before it reaches
/// `CanvasUIView.touchesBegan`, causing `touches.count` to always be 1 even when
/// `isMultipleTouchEnabled = true`.
///
/// This recognizer:
/// - Never actually "recognizes" — it always stays in `.possible` and then `.failed`.
/// - Sets `cancelsTouchesInView = false` and `delaysTouchesBegan = false` so it
///   never interferes with the view's own `touchesBegan/Moved/Ended/Cancelled` delivery.
/// - Implements `UIGestureRecognizerDelegate` to return `true` for all simultaneous
///   recognition requests, forcing coexistence rather than competition.
private final class MultiTouchPassthroughRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {

    init() {
        super.init(target: nil, action: nil)
        self.delegate = self
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }

    // Always fail — we never want to claim recognition, just coexist.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { false }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { false }
}

// MARK: - TouchEventSink

/// Protocol for receiving batched touch samples from the canvas UIView layer.
///
/// The canvas adapter (`CanvasUIView`) calls `ingest(_:phase:)` once per
/// `touchesBegan/Moved/Ended/Cancelled` call, forwarding ALL active touches in
/// the event as a flat array of `TouchSample` values.
///
/// Conformors (typically the view model) are responsible for routing samples
/// through `TouchRouter`.
///
/// `@MainActor` — UIKit touch callbacks are always delivered on the main thread;
/// requiring `@MainActor` here avoids actor-isolation mismatches with
/// `@MainActor`-isolated view model conformers.
@MainActor
public protocol TouchEventSink: AnyObject {
    func ingest(_ samples: [TouchSample], phase: TouchPhase)
}

// MARK: - CanvasUIView

/// Pure UIKit adapter: converts UITouch events into `TouchSample` arrays and
/// forwards them to an injected `TouchEventSink`.
///
/// This class contains ZERO business logic. Its sole responsibility is bridging
/// the UIKit touch delivery system to the pure-Swift `TouchSample` / `TouchPhase`
/// layer that `TouchRouter` understands.
///
/// # Why UIView?
/// SwiftUI's `DragGesture` and `.gesture(_:)` modifiers lose low-level touch
/// events in complex simultaneous-gesture scenarios. Overriding
/// `touchesBegan/Moved/Ended/Cancelled` on a raw `UIView` gives us direct
/// access to every `UITouch` with sub-millisecond timestamps and coalescence.
///
/// # Deadzones
/// SwiftUI overlays (sidebar, HUD buttons) sit above the canvas in the ZStack,
/// but because the canvas UIView spans the full screen, UIKit hit-testing would
/// normally deliver touches that land inside SwiftUI controls to both layers.
/// Setting `deadzones` causes `point(inside:with:)` to return `false` for those
/// regions, letting SwiftUI's controls receive the touch instead.
///
/// # Testing
/// Raw `UIView` touch overrides cannot be unit-tested without a running UI host.
/// See `InkBridgeIOSTests/InputTests/README.md`. The `TouchRouter` consumed
/// downstream IS fully unit-tested.
public final class CanvasUIView: UIView {

    /// Injected sink. Typically the `CaptureScreenViewModel` (Batch 6).
    /// Weak to avoid a retain cycle with the SwiftUI representable.
    public weak var sink: TouchEventSink?

    /// Rects (in this view's coordinate space) where touches should NOT be consumed
    /// by the canvas. Set by `CanvasRepresentable.updateUIView` whenever the layout
    /// changes. Used to let SwiftUI sidebar and HUD button taps through.
    public var deadzones: [CGRect] = []

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // Bug 4 fix: install a pass-through recognizer that forces SwiftUI's implicit
        // gesture recognizers (pan, tap, etc.) to allow simultaneous recognition with
        // our raw UIView touch delivery. Without this, the second finger is consumed by
        // a SwiftUI ancestor recognizer and never arrives in touchesBegan.
        addGestureRecognizer(MultiTouchPassthroughRecognizer())
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(MultiTouchPassthroughRecognizer())
    }

    // MARK: - Hit-testing

    /// Returns `false` for points inside any deadzone so SwiftUI overlays get the touch.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for zone in deadzones {
            if zone.contains(point) { return false }
        }
        return super.point(inside: point, with: event)
    }

    // MARK: - Touch overrides

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Bug 4 diagnostic: if count is always 1, ancestor recognizer ate the 2nd finger.
        print("[CanvasUIView] touchesBegan count=\(touches.count) allTouches=\(event?.allTouches?.count ?? 0)")
        guard let sink else { return }
        let samples = makeSamples(from: touches)
        sink.ingest(samples, phase: .began)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let sink else { return }
        let samples = makeSamples(from: touches)
        sink.ingest(samples, phase: .moved)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Bug 3 diagnostic: confirm ended phase is forwarded for tap classification.
        print("[CanvasUIView] touchesEnded count=\(touches.count)")
        guard let sink else { return }
        let samples = makeSamples(from: touches)
        sink.ingest(samples, phase: .ended)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let sink else { return }
        let samples = makeSamples(from: touches)
        sink.ingest(samples, phase: .cancelled)
    }

    // MARK: - Private helpers

    private func makeSamples(from touches: Set<UITouch>) -> [TouchSample] {
        touches.map { touch in
            // UITouch.hashValue is stable for the lifetime of the touch object.
            // We wrap it in a UUID via a deterministic mapping so TouchSample
            // can remain independent of UIKit.
            let id = UUID(uuidString: "00000000-0000-0000-\(String(format: "%04X", touch.hashValue & 0xFFFF))-\(String(format: "%012X", abs(touch.hashValue)))") ?? UUID()
            return TouchSample(
                id: id,
                location: touch.location(in: self),
                timestamp: touch.timestamp
            )
        }
    }
}
