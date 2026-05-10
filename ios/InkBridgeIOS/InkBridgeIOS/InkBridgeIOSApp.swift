import SwiftUI

// MARK: - InkBridgeIOSApp

/// SwiftUI `@main` entry point.
///
/// Wires:
/// - `AppDelegate` for landscape orientation lock (belt-and-suspenders with Info.plist).
/// - `AppContainer` (composition root) for all dependency construction.
/// - `RootView` as the single `WindowGroup` content.
@main
struct InkBridgeIOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView(
                connectionViewModel: container.connectionViewModel,
                captureViewModel: container.captureViewModel,
                profileStore: container.profileStore,
                settingsRepo: container.settingsRepo
            )
        }
    }
}
