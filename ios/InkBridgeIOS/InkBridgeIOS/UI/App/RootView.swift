import SwiftUI

// MARK: - RootView

/// Top-level routing view that switches between `ConnectionScreen` and
/// `CaptureScreen` based on the current `ConnectionState`.
///
/// # Routing logic
/// | `connectionState`          | Shows          |
/// |----------------------------|----------------|
/// | `.idle`                    | ConnectionScreen |
/// | `.connecting`              | ConnectionScreen (with spinner in connect button) |
/// | `.failed`                  | ConnectionScreen (with permission banner) |
/// | `.connected`               | CaptureScreen  |
///
/// # Scene-phase forwarding
/// The view subscribes to `@Environment(\.scenePhase)` and forwards every change
/// to `connectionViewModel.handleScenePhase(_:)` so the transport is properly
/// torn down when the app enters the background.
///
/// # App entry point
/// `@main` lives in `InkBridgeIOSApp.swift` (Batch 7 — J.2). For now `RootView`
/// is a plain `View` that the App struct's `WindowGroup` body will instantiate.
public struct RootView: View {

    @State var connectionViewModel: ConnectionViewModel
    @State var captureViewModel: CaptureViewModel
    @Environment(\.scenePhase) private var scenePhase

    // Injected from the composition root so CaptureScreen can open the settings sheet.
    let profileStore: ProfileStore
    let settingsRepo: any SettingsRepository

    public init(
        connectionViewModel: ConnectionViewModel,
        captureViewModel: CaptureViewModel,
        profileStore: ProfileStore,
        settingsRepo: any SettingsRepository
    ) {
        self._connectionViewModel = State(initialValue: connectionViewModel)
        self._captureViewModel = State(initialValue: captureViewModel)
        self.profileStore = profileStore
        self.settingsRepo = settingsRepo
    }

    public var body: some View {
        let _ = print("[Root] body, state=\(connectionViewModel.connectionState)")
        Group {
            switch connectionViewModel.connectionState {
            case .connected:
                CaptureScreen(
                    viewModel: captureViewModel,
                    profileStore: profileStore,
                    settingsRepo: settingsRepo,
                    onDisconnect: {
                        // Bug 2 fix: disconnect via ConnectionViewModel so RootView's
                        // observed connectionState actually changes to .idle and the
                        // Group switches back to ConnectionScreen.
                        connectionViewModel.disconnect()
                    }
                )
            default:
                ConnectionScreen(viewModel: connectionViewModel)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            connectionViewModel.handleScenePhase(newPhase)
        }
        .onChange(of: connectionViewModel.connectionState) { _, newState in
            // Mirror connection state into the capture view model so CaptureScreen
            // can display the status pill with the correct state.
            captureViewModel.updateConnectionState(newState)
        }
    }
}
