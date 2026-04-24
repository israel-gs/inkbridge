import SwiftUI

/// Accessibility permission onboarding screen.
///
/// Displayed when `AXIsProcessTrusted()` returns false.
/// Polls for permission grant every 1 second via ``ServerViewModel``.
/// ui.md R6, macos-injection.md R1.
struct OnboardingView: View {

    @ObservedObject var viewModel: ServerViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            Text("Accessibility Access Required")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(
                "InkBridge needs Accessibility permission to inject stylus events " +
                "into drawing applications. Without it, pressure and tilt data cannot " +
                "reach Procreate, Affinity, or any other app."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    viewModel.openAccessibilitySettings()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button("I've enabled it — Recheck") {
                    viewModel.recheckPermission()
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(minWidth: 380, minHeight: 300)
    }
}

// MARK: - Previews

#Preview("Onboarding — Light") {
    OnboardingView(viewModel: PreviewServerViewModel.make())
        .preferredColorScheme(.light)
}

#Preview("Onboarding — Dark") {
    OnboardingView(viewModel: PreviewServerViewModel.make())
        .preferredColorScheme(.dark)
}
