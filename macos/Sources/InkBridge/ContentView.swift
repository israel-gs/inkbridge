import SwiftUI
import InkBridgeCore

/// Root view — switches between onboarding and status based on Accessibility trust.
///
/// ui.md R5, R6, R7.
struct ContentView: View {

    @StateObject private var viewModel = ServerViewModel()

    var body: some View {
        Group {
            if viewModel.isTrusted {
                StatusView(viewModel: viewModel)
            } else {
                OnboardingView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        // When the tablet asks for a key capture, surface the modal here so
        // it works regardless of which child view is currently rendered.
        .sheet(
            item: Binding(
                get: { viewModel.pendingCapture },
                // Setter is invoked when the sheet dismisses itself. The
                // capture flow always finishes by calling submitCapture or
                // cancelCapture, both of which clear the server-side state;
                // this setter is therefore a no-op.
                set: { _ in }
            )
        ) { request in
            CaptureKeyView(
                slotId: request.slotId,
                onSubmit: { vk, mods in viewModel.submitCapture(virtualKey: vk, modifierFlags: mods) },
                onCancel: { viewModel.cancelCapture() }
            )
        }
    }
}

// Sheets need an Identifiable item; reuse the slotId as the stable identity.
extension InkBridgeServer.PendingCaptureRequest: Identifiable {
    public var id: UInt8 { slotId }
}
