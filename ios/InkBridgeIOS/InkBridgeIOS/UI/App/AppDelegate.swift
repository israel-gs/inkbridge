import UIKit

// MARK: - AppDelegate

/// Backstop for landscape orientation lock.
///
/// The `Info.plist` build setting
/// `INFOPLIST_KEY_UISupportedInterfaceOrientations = LandscapeLeft LandscapeRight`
/// is the primary gate. This delegate provides a belt-and-suspenders guarantee by
/// enforcing `.landscape` programmatically — handles edge cases where UIKit
/// overrides the plist value (e.g. child view controllers that request rotation).
///
/// Wired via `@UIApplicationDelegateAdaptor(AppDelegate.self)` in `InkBridgeIOSApp`.
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscape
    }
}
