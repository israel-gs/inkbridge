import SwiftUI
import UIKit

// MARK: - ExpressKeysSidebar

/// Vertical strip of 6 Express Key buttons overlaid on the capture canvas.
///
/// # Behavior parity with Android `ExpressKeyBar`
/// - One-shot keys (`.oneShot`) fire `[KEY_DOWN, KEY_UP]` atomically on press.
/// - Modifier-hold keys (`.modifierHold`) fire `KEY_DOWN` on press and `KEY_UP` on release.
/// - Haptic feedback fires on every press (`UIImpactFeedbackGenerator(.light)`).
/// - Buttons animate scale on press (parity with Android's `animateFloatAsState` 0.95 scale).
/// - Empty labels show a placeholder dot so the slot is still tappable.
///
/// # Layout
/// - Width: 64 pt fixed.
/// - Height: full screen height (`.frame(maxHeight: .infinity)`).
/// - Positioned via the parent `HStack` spacer pattern in `CaptureScreen`.
public struct ExpressKeysSidebar: View {

    let profile: ExpressKeyProfile
    let edge: SidebarEdge
    let onKeyEvent: (StylusEvent) -> Void

    public init(
        profile: ExpressKeyProfile,
        edge: SidebarEdge,
        onKeyEvent: @escaping (StylusEvent) -> Void
    ) {
        self.profile = profile
        self.edge = edge
        self.onKeyEvent = onKeyEvent
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(profile.keys.enumerated()), id: \.offset) { index, key in
                ExpressKeyButton(
                    key: key,
                    onKeyEvent: onKeyEvent
                )
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - ExpressKeyButton

/// A single tappable / long-pressable Express Key button.
private struct ExpressKeyButton: View {

    let key: ExpressKey
    let onKeyEvent: (StylusEvent) -> Void

    @State private var isPressed: Bool = false

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        let cyan = Color(red: 0, green: 0.784, blue: 1)  // #00C8FF
        let idleBg = Color.white.opacity(0.06)
        let idleBorder = Color.white.opacity(0.12)
        let pressedBg = cyan.opacity(key.holdMode == .modifierHold ? 0.28 : 0.18)
        let pressedBorder = cyan.opacity(0.6)

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPressed ? pressedBg : idleBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPressed ? pressedBorder : idleBorder, lineWidth: 1)
                )

            VStack(spacing: 2) {
                Text(key.label.isEmpty ? "·" : key.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isPressed ? cyan : Color.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if key.holdMode == .modifierHold && isPressed {
                    Text("HELD")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(cyan)
                }
            }
            .padding(4)
        }
        .frame(width: 52, height: 52)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isPressed)
        .gesture(pressGesture)
    }

    // MARK: - Gesture

    /// Combines a long-press gesture (for modifier-hold detection) with a tap.
    /// On iOS, we use `DragGesture` with `minimumDistance: 0` to get precise
    /// press/release callbacks without the 0.5 s long-press delay.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    feedbackGenerator.impactOccurred()
                    // Emit press events
                    let pressEvents = ExpressKeyDispatcher.events(for: key, phase: .pressed)
                    pressEvents.forEach { onKeyEvent($0) }
                }
            }
            .onEnded { _ in
                if isPressed {
                    isPressed = false
                    // Emit release events
                    let releaseEvents = ExpressKeyDispatcher.events(for: key, phase: .released)
                    releaseEvents.forEach { onKeyEvent($0) }
                }
            }
    }
}
