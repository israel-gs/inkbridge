import Foundation

// MARK: - AppContainer

/// Composition root for the InkBridge iOS app.
///
/// Owns and wires all top-level dependencies. Constructed once in `InkBridgeIOSApp`
/// so the `App` struct stays minimal (no dependency construction logic in body).
///
/// # Ownership rules
/// - `udpClient` is shared between `connectionViewModel` and `captureViewModel`
///   so both operate on the same transport layer.
/// - `settingsRepo` is shared between `connectionViewModel` and `captureViewModel`
///   for reading port/host defaults.
final class AppContainer: ObservableObject {

    // MARK: - Shared dependencies

    let udpClient: NWConnectionUDPClient
    let discovery: BSDBroadcastDiscovery
    let settingsRepo: UserDefaultsSettingsRepository
    let profileStore: ProfileStore

    // MARK: - ViewModels

    let connectionViewModel: ConnectionViewModel
    let captureViewModel: CaptureViewModel

    // MARK: - Init

    @MainActor
    init() {
        self.udpClient = NWConnectionUDPClient()
        self.discovery = BSDBroadcastDiscovery()
        self.settingsRepo = UserDefaultsSettingsRepository()
        self.profileStore = ProfileStore()

        self.connectionViewModel = ConnectionViewModel(
            udpClient: udpClient,
            discovery: discovery
        )

        // Load the persisted profile list and pick the first profile (the active one).
        // Without this, CaptureViewModel defaults to ExpressKeyProfile.makeDefault()
        // which has all-empty labels, causing the Express Keys sidebar to show blank buttons.
        let storedProfiles = profileStore.loadProfiles()
        let initialProfile = storedProfiles.first ?? .makeDefault()
        print("[AppContainer] loaded \(storedProfiles.count) profile(s); active=\(initialProfile.name)")

        self.captureViewModel = CaptureViewModel(
            udpClient: udpClient,
            settingsRepo: settingsRepo,
            activeProfile: initialProfile
        )
    }
}
