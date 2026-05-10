import SwiftUI
import UIKit

/// SwiftUI bridge that wraps `CanvasUIView` for embedding in the `CaptureScreen`.
///
/// Forwards an injected `TouchEventSink` (typically the view model) into the
/// underlying `CanvasUIView` on every `updateUIView` call so that sink-reference
/// changes are propagated correctly when the environment changes.
///
/// `deadzones` are rects (in screen coordinates) where the canvas should yield
/// hit-testing to SwiftUI overlays above it (sidebar, HUD buttons).
public struct CanvasRepresentable: UIViewRepresentable {

    /// The sink that receives `TouchSample` batches from the UIView layer.
    /// Use `any` existential so callers can inject any concrete type without
    /// generics leaking into the SwiftUI view tree.
    public let sink: any TouchEventSink

    /// Rects in the view's own coordinate space where touches pass through to
    /// SwiftUI controls (sidebar and HUD row). Updated on every layout pass.
    public var deadzones: [CGRect]

    public init(sink: any TouchEventSink, deadzones: [CGRect] = []) {
        self.sink = sink
        self.deadzones = deadzones
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> CanvasUIView {
        let view = CanvasUIView()
        view.sink = sink
        // Clear so the SwiftUI dot-grid drawn behind the UIView shows through.
        view.backgroundColor = .clear
        // Allow up to 10 simultaneous touches — required for 2-finger scroll/zoom
        // gesture routing in TouchRouter. UIView defaults to false.
        view.isMultipleTouchEnabled = true
        return view
    }

    public func updateUIView(_ uiView: CanvasUIView, context: Context) {
        // Propagate sink changes (e.g. after view model recreation).
        uiView.sink = sink
        // Propagate deadzone changes on every layout update.
        uiView.deadzones = deadzones
    }
}
