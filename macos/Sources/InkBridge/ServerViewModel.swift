import SwiftUI
import Combine
import Foundation
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
    @Published private(set) var pendingCapture: InkBridgeServer.PendingCaptureRequest?

    /// Position smoothing on/off. Persisted across launches.
    @Published var smoothingEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(smoothingEnabled, forKey: Self.smoothingKey)
            server.setSmoothingEnabled(smoothingEnabled)
        }
    }

    /// Show the live latency histogram in StatusView. Persisted across launches.
    @Published var showLatencyChart: Bool = false {
        didSet {
            UserDefaults.standard.set(showLatencyChart, forKey: Self.histogramKey)
        }
    }

    /// Currently-selected default pressure curve. Mirrors `curveRegistry.defaultCurve`.
    /// Published so SwiftUI redraws the picker when the underlying registry changes.
    @Published var defaultCurve: PressureCurve = .linear

    /// Public accessor so the settings sheet can read/write per-app overrides.
    let curveRegistry: CurveRegistry
    let frontmostApp: FrontmostAppDetector

    private static let smoothingKey = "signalq.smoothing"
    private static let histogramKey = "signalq.histogram"

    // MARK: - Private

    private let server: InkBridgeServer
    private let tunnelMaintainer: UsbTunnelMaintainer
    private let broadcastResponder: BroadcastResponder?
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private let port: UInt16 = 4545
    private let probePort: UInt16 = 4546

    /// Retained so that [refreshInjectorTrust] can call [Injector.refreshTrust].
    /// Bug 7 fix: inject() no longer calls AXIsProcessTrustedWithOptions on every frame;
    /// instead it reads the cached isTrusted field.  We must ensure
    /// that field is kept current by calling [Injector.refreshTrust] here.
    private let injector: any Injector

    // MARK: - Init

    init() {
        let injector = CGEventInjector()
        self.injector = injector

        // Mac name shown to clients during discovery. Prefer the user-facing
        // localized name (from System Settings → General → About), fall back
        // to the POSIX hostname, and finally a literal "Mac".
        let macName: String = {
            let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            return name.isEmpty ? "Mac" : name
        }()

        self.server = InkBridgeServer(injector: injector)
        self.broadcastResponder = BroadcastResponder(
            probePort: probePort,
            dataPort: port,
            hostname: macName,
        )
        self.isTrusted = injector.isTrusted

        // Build pressure-curve registry + frontmost-app detector and wire the
        // injector so every STYLUS_MOVE pressure value passes through the
        // resolved curve before being posted as a tablet event.
        let registry = CurveRegistry(store: UserDefaultsCurveStore())
        let detector = FrontmostAppDetector()
        self.curveRegistry = registry
        self.frontmostApp = detector
        self.defaultCurve = registry.defaultCurve
        injector.pressureTransform = { [registry, detector] raw in
            registry.curve(for: detector.currentBundleId).apply(raw)
        }

        // Load persisted signal-quality preferences. UserDefaults returns false
        // for an unset Bool, so smoothing defaults to true via explicit fallback.
        let defaults = UserDefaults.standard
        let smoothingDefault = defaults.object(forKey: Self.smoothingKey) as? Bool ?? true
        self.smoothingEnabled = smoothingDefault
        self.showLatencyChart = defaults.bool(forKey: Self.histogramKey)
        // Apply current preference to the server now that both are constructed.
        self.server.setSmoothingEnabled(smoothingDefault)

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

        server.$pendingCaptureRequest
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingCapture)

        tunnelMaintainer.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$tunnelState)

        if isTrusted {
            server.start(port: port)
            startBroadcastResponder()
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
        self.broadcastResponder = nil
        self.curveRegistry = CurveRegistry(store: UserDefaultsCurveStore())
        self.frontmostApp = FrontmostAppDetector(provider: { nil })
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
            startBroadcastResponder()
        }
    }

    private func startBroadcastResponder() {
        guard let responder = broadcastResponder, !responder.isRunning else { return }
        do {
            try responder.start()
        } catch {
            NSLog("[ServerViewModel] BroadcastResponder failed to start: \(error)")
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
        broadcastResponder?.stop()
    }

    // MARK: - Express-key remote capture

    /// Sends the captured key combo back to the tablet for the pending slot.
    func submitCapture(virtualKey: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard let request = pendingCapture else { return }
        var bits: UInt8 = 0
        if modifierFlags.contains(.command)  { bits |= 0x01 } // CMD
        if modifierFlags.contains(.control)  { bits |= 0x02 } // CTRL
        if modifierFlags.contains(.option)   { bits |= 0x04 } // OPT
        if modifierFlags.contains(.shift)    { bits |= 0x08 } // SHIFT

        // virtualKey is the Carbon-era kVK_*; clamp to u8 (all printable
        // keys + arrows + F-keys fit in 8 bits — kVK_F12 = 0x6F).
        let keyCode = UInt8(truncatingIfNeeded: virtualKey)
        server.submitCaptureResponse(
            slotId: request.slotId,
            keyCode: keyCode,
            modifiers: bits,
            cancelled: false
        )
    }

    /// User dismissed the capture modal without pressing a key.
    func cancelCapture() {
        guard let request = pendingCapture else { return }
        server.submitCaptureResponse(
            slotId: request.slotId,
            keyCode: 0,
            modifiers: 0,
            cancelled: true
        )
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
