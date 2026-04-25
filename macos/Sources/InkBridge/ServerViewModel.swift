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

    /// Retained so that [refreshInjectorTrust] can call [Injector.refreshTrust].
    /// Bug 7 fix: inject() no longer calls AXIsProcessTrustedWithOptions on every frame;
    /// instead it reads the cached isTrusted field.  We must ensure
    /// that field is kept current by calling [Injector.refreshTrust] here.
    private let injector: any Injector

    // MARK: - Init

    init() {
        let injector = CGEventInjector()
        self.injector = injector
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

        // Bug 7 fix: refresh injector trust when the app returns to foreground.
        // The user may have toggled Accessibility in System Settings while the app
        // was backgrounded. NSApplication.willBecomeActiveNotification fires before
        // the first event delivery after foreground return — ideal for a one-shot
        // trust re-read without a syscall on every inject() call.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshInjectorTrust()
        }
    }

    /// Preview / test initialiser — uses MockInjector, no-op listeners, no real ports.
    init(previewState: ServerState, isTrusted: Bool, tunnelState: UsbTunnelState = .idle) {
        let mock = MockInjector()
        self.injector = mock
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
        refreshInjectorTrust()
        if isTrusted {
            stopPermissionPolling()
            server.start(port: port)
        }
    }

    /// Calls [Injector.refreshTrust] and syncs the published [isTrusted] field.
    ///
    /// Bug 7 fix: [CGEventInjector.inject] no longer re-reads trust on every frame;
    /// this method keeps the cached field up-to-date. [Injector.refreshTrust] updates
    /// the injector's internal isTrusted cache; we read the system value separately to
    /// update the ViewModel's own published [isTrusted] so the UI stays in sync.
    private func refreshInjectorTrust() {
        injector.refreshTrust()
        isTrusted = AXIsProcessTrusted()
    }

    /// Stop the server manually.
    func stopServer() {
        server.stop()
    }

    /// Start the server manually. Only meaningful when state is `.idle` and
    /// Accessibility is granted; otherwise it's a no-op (start would fail or
    /// the user must grant permission first).
    func startServer() {
        guard isTrusted else { return }
        server.start(port: port)
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
