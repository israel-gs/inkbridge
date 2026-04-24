import SwiftUI
import Combine
import InkBridgeCore
import ApplicationServices
import CoreGraphics

/// ViewModel bridging ``InkBridgeServer`` to the SwiftUI layer.
///
/// Owns the server lifecycle and exposes observable state for views.
/// Polls `AXIsProcessTrusted()` while in onboarding to detect permission grant.
/// macos-injection.md R1, ui.md R5-R7.
@MainActor
final class ServerViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var serverState: ServerState = .idle
    @Published private(set) var stats: Stats = Stats()
    @Published private(set) var latency: LatencyTracker.Snapshot = .zero
    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var tunnelState: UsbTunnelState = .idle

    // MARK: - Private

    private let server: InkBridgeServer
    private let tunnelMaintainer: UsbTunnelMaintainer
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private let port: UInt16 = 4545

    // MARK: - Init

    init() {
        let injector = CGEventInjector()
        self.server = InkBridgeServer(injector: injector)
        self.isTrusted = injector.isTrusted

        let adbPath = AdbDiscovery.findAdb()
        let runner: AdbRunner? = adbPath.map { ProcessAdbRunner(adbPath: $0) }
        self.tunnelMaintainer = UsbTunnelMaintainer(runner: runner, port: port)

        server.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$serverState)

        server.$stats
            .receive(on: DispatchQueue.main)
            .assign(to: &$stats)

        server.$latency
            .receive(on: DispatchQueue.main)
            .assign(to: &$latency)

        tunnelMaintainer.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$tunnelState)

        if isTrusted {
            server.start(port: port)
        } else {
            startPermissionPolling()
        }

        tunnelMaintainer.start()
    }

    /// Preview / test initialiser — uses MockInjector, no-op listeners, no real ports.
    init(previewState: ServerState, isTrusted: Bool, tunnelState: UsbTunnelState = .idle) {
        let mock = MockInjector()
        self.server = InkBridgeServer(
            injector: mock,
            udpListener: NoOpListener(),
            tcpListener: NoOpListener(),
            displayRect: DisplayRect(width: 1920, height: 1080)
        )
        self.isTrusted = isTrusted
        self.serverState = previewState
        self.tunnelMaintainer = UsbTunnelMaintainer(runner: Optional<ProcessAdbRunner>.none, port: 4545)
        self.tunnelState = tunnelState
    }

    // MARK: - Public actions

    /// Open System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Re-evaluate Accessibility trust immediately (bound to "I've enabled it — Recheck").
    func recheckPermission() {
        let trusted = AXIsProcessTrusted()
        isTrusted = trusted
        if trusted {
            stopPermissionPolling()
            server.start(port: port)
        }
    }

    /// Stop the server manually.
    func stopServer() {
        server.stop()
    }

    // MARK: - Permission polling (≤2 second interval per macos-injection.md R1)

    private func startPermissionPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                await MainActor.run {
                    self?.recheckPermission()
                }
            }
        }
    }

    private func stopPermissionPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
