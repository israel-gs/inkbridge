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
    }
}
