#if canImport(AppKit)
import AppKit
#endif
import Foundation

/// Caches `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` so the
/// inject hot path can read it without a syscall on every frame.
///
/// The cache refreshes on `NSWorkspace.didActivateApplicationNotification`,
/// which fires whenever the user switches apps. Reading the cached value is a
/// pure property access.
///
/// `provider` is injected so unit tests can supply a deterministic source
/// without touching `NSWorkspace`.
@MainActor
public final class FrontmostAppDetector {

    private let provider: () -> String?
    public private(set) var currentBundleId: String?

    /// Designated initialiser (testable).
    public init(provider: @escaping () -> String?) {
        self.provider = provider
        self.currentBundleId = provider()
    }

    #if canImport(AppKit)
    /// Convenience initialiser bound to `NSWorkspace`. Subscribes to the
    /// app-activation notification so the cache stays fresh.
    public convenience init(workspace: NSWorkspace = .shared) {
        self.init(provider: { workspace.frontmostApplication?.bundleIdentifier })
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            // Hop to MainActor explicitly — the closure is nonisolated even
            // though we requested .main queue, due to Swift 6 strict concurrency.
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
    #endif

    /// Re-reads from the provider and updates the cache. Call manually after
    /// state the provider depends on may have changed.
    public func refresh() {
        currentBundleId = provider()
    }
}
