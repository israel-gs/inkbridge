import Foundation
import Observation
import SwiftUI

// MARK: - ConnectionViewModel

/// Manages discovery, manual-IP entry, connection lifecycle, and scene-phase
/// transitions for the Connection screen.
///
/// # Responsibilities
/// - Subscribes to `BroadcastDiscovery.hosts` AsyncStream and maintains a
///   deduplicated list of `DiscoveredHost` values for display.
/// - Exposes `hostField: String` for the manual IP text field.
/// - Calls `udpClient.connect` on discovery tap or manual connect.
/// - Calls `udpClient.disconnect` when scene enters background.
/// - Surfaces Local Network permission denial as `connectionState == .failed`.
///
/// # Main-actor isolation
/// All mutations to `@Observable` properties happen on `@MainActor` so SwiftUI
/// reads are always on the main thread.
@Observable
@MainActor
public final class ConnectionViewModel {

    // MARK: - Observed Properties

    /// Hosts discovered via broadcast. Deduped by (ip, port); updated in real time.
    public private(set) var discoveredHosts: [DiscoveredHost] = []

    /// Text field content for manual IP/hostname entry.
    public var hostField: String = ""

    /// UDP port for manual connection. Default: 4545 (spec §Discovery).
    public var port: UInt16 = 4545

    /// The current connection state, mirrored from the `UDPClient`.
    public private(set) var connectionState: ConnectionState = .idle

    // MARK: - Dependencies

    private let udpClient: any UDPClient
    private let discovery: any BroadcastDiscovery
    /// Optional settings repo — when provided, `autoReconnect` gates foreground reconnect.
    private let settingsRepo: (any SettingsRepository)?

    // MARK: - Internal state

    private var discoveryTask: Task<Void, Never>?
    /// The last successfully connected host. Used to auto-reconnect on foreground.
    private var lastConnectedHost: DiscoveredHost?

    // MARK: - Init

    public init(
        udpClient: any UDPClient,
        discovery: any BroadcastDiscovery,
        settingsRepo: (any SettingsRepository)? = nil
    ) {
        self.udpClient = udpClient
        self.discovery = discovery
        self.settingsRepo = settingsRepo
    }

    // MARK: - Lifecycle

    /// Starts the background discovery subscription.
    /// Call once when the view appears.
    ///
    /// # Ordering note
    /// `discovery.hosts` (a lazy `AsyncStream`) installs the continuation on first
    /// access. The stream MUST be accessed — i.e. the `for await` loop must begin —
    /// before `discovery.start()` spawns its recv loop; otherwise replies that arrive
    /// before the stream is consumed are silently dropped because the continuation is nil.
    /// We achieve this by starting the iteration task first, then calling `start()`.
    public func startDiscovery() {
        // Idempotent: if a discovery task is already running, do nothing.
        // RootView/onAppear may fire multiple times; cancelling the in-flight
        // task would close the AsyncStream's only iterator, and since
        // `BroadcastDiscovery.hosts` is a single-consumer `lazy var`, a new
        // `for await` would immediately exit and miss every yielded host.
        if let existing = discoveryTask, !existing.isCancelled {
            print("[ConnectionViewModel] startDiscovery skipped — task already running")
            return
        }
        print("[ConnectionViewModel] startDiscovery called")
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            // Kick off start() concurrently — do NOT await it before entering the
            // for-await loop. The Task captures `self` strongly for its duration.
            Task {
                do {
                    print("[ConnectionViewModel] discovery.start() called")
                    try await discovery.start()
                    print("[ConnectionViewModel] discovery.start() completed")
                } catch {
                    print("[ConnectionViewModel] discovery.start() error: \(error)")
                    // Non-fatal: permission denied surfaces as no hosts arriving.
                }
            }
            // Subscribe to the stream. This accesses `discovery.hosts` for the
            // first time, installing the continuation before any replies arrive.
            print("[ConnectionViewModel] entering hosts stream loop")
            for await host in discovery.hosts {
                guard !Task.isCancelled else { break }
                print("[ConnectionViewModel] discovered host: \(host.name) \(host.ipv4):\(host.port)")
                await MainActor.run {
                    self.upsertHost(host)
                }
            }
            print("[ConnectionViewModel] hosts stream loop exited")
        }
    }

    /// Stops the discovery subscription.
    public func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        Task { await discovery.stop() }
    }

    // MARK: - Connection

    /// Connects to the given discovered host.
    public func connect(to host: DiscoveredHost) {
        hostField = host.ipv4
        port = host.port
        connect()
    }

    /// Connects using the current `hostField` and `port` values.
    public func connect() {
        let ip = hostField.trimmingCharacters(in: .whitespaces)
        guard !ip.isEmpty else { return }
        connectionState = .connecting

        Task { [weak self] in
            guard let self else { return }
            do {
                try await udpClient.connect(host: ip, port: port)
                // Build a synthetic DiscoveredHost for the connected state.
                let host = DiscoveredHost(
                    name: ip,
                    ipv4: ip,
                    port: port,
                    lastSeen: Date()
                )
                await MainActor.run {
                    self.connectionState = .connected(host: host)
                    self.lastConnectedHost = host
                }
            } catch {
                let reason = error.localizedDescription
                await MainActor.run { self.connectionState = .failed(reason: reason) }
            }
        }
    }

    /// Disconnects from the current host. Clears the last-connected host cache.
    public func disconnect() {
        print("[ConnectionViewModel] disconnect() called, state was \(connectionState)")
        lastConnectedHost = nil
        connectionState = .idle
        print("[ConnectionViewModel] state now \(connectionState)")
        Task { await udpClient.disconnect() }
    }

    // MARK: - Scene-phase handling

    /// Call when the app's scene phase changes.
    /// - Disconnects when entering `.background` (preserves `lastConnectedHost`).
    /// - Resumes discovery and attempts auto-reconnect when entering `.active`.
    public func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // Preserve lastConnectedHost so foreground can reconnect.
            connectionState = .idle
            Task { await udpClient.disconnect() }
        case .active:
            startDiscovery()
            // Auto-reconnect when a prior host exists and the setting is enabled.
            // When settingsRepo is nil (legacy / test path) we default to allowing reconnect.
            let shouldReconnect = settingsRepo?.autoReconnect ?? true
            if shouldReconnect, let host = lastConnectedHost {
                connect(to: host)
            }
        default:
            break
        }
    }

    // MARK: - Private helpers

    private func upsertHost(_ host: DiscoveredHost) {
        if let idx = discoveredHosts.firstIndex(where: { $0 == host }) {
            discoveredHosts[idx].name = host.name
            discoveredHosts[idx].lastSeen = host.lastSeen
        } else {
            discoveredHosts.append(host)
        }
    }
}
