import Foundation
import InkBridgeCore

/// Factory for preview-safe ``ServerViewModel`` stubs.
///
/// Uses ``MockInjector`` + no-op listeners so previews don't bind real ports
/// or require Accessibility permission.
enum PreviewServerViewModel {

    @MainActor
    static func make() -> ServerViewModel {
        ServerViewModel(previewState: .idle, isTrusted: false)
    }

    @MainActor
    static func makeListening() -> ServerViewModel {
        ServerViewModel(previewState: .listening(port: 4545), isTrusted: true)
    }

    @MainActor
    static func makeDegraded() -> ServerViewModel {
        ServerViewModel(previewState: .degraded(reason: "Port in use"), isTrusted: true)
    }

    @MainActor
    static func makeListeningWithTunnel(_ tunnelState: UsbTunnelState) -> ServerViewModel {
        ServerViewModel(
            previewState: .listening(port: 4545),
            isTrusted: true,
            tunnelState: tunnelState
        )
    }
}
