import SwiftUI

// MARK: - CaptureScreen

/// Full-screen capture surface that wraps `CanvasUIView` (via `CanvasRepresentable`),
/// the Express Keys sidebar, connection-state pill, settings button, and disconnect button.
///
/// # Design constraints (per spec §Edge-Swipe Suppression)
/// - `.statusBarHidden(true)` — hides iOS status bar.
/// - `.persistentSystemOverlays(.hidden)` — removes home indicator / swipe handles.
/// - `.defersSystemGestures(.bottom)` — requires a second-swipe for system gesture at bottom.
///
/// # Hit-testing
/// The canvas UIView spans the entire screen. `CanvasUIView.point(inside:with:)` is
/// overridden to return `false` inside `deadzones` — the rects occupied by the sidebar
/// and the HUD button row — so those SwiftUI controls receive touches normally.
/// Deadzones are measured via `GeometryReader` anchors and passed into `CanvasRepresentable`.
///
/// Batch 6 (I.4): replaced `CaptureScreenViewModelProtocol` with concrete `CaptureViewModel`.
public struct CaptureScreen: View {

    @State private var viewModel: CaptureViewModel
    let onDisconnect: () -> Void
    @State private var showSettings: Bool = false
    /// When true, all HUD chrome fades out; only the fullscreen-toggle stays visible.
    @State private var isFullscreen: Bool = false

    /// Rects accumulated from sidebar and HUD backgrounds, forwarded to the canvas as deadzones.
    @State private var deadzones: [CGRect] = []

    /// `profileStore` + `settingsRepo` are injected from the composition root so the
    /// settings sheet can load and persist Express Key profiles.
    let profileStore: ProfileStore
    let settingsRepo: any SettingsRepository

    public init(
        viewModel: CaptureViewModel,
        profileStore: ProfileStore,
        settingsRepo: any SettingsRepository,
        onDisconnect: @escaping () -> Void
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.profileStore = profileStore
        self.settingsRepo = settingsRepo
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        GeometryReader { fullGeo in
            ZStack(alignment: .topLeading) {
                // LAYER 0 — OLED-friendly near-black base (extends under safe-area).
                Color.inkBlack.ignoresSafeArea()

                // LAYER 0.5 — Dot grid (visual parity with Android). Drawn in SwiftUI
                // so it sits behind the transparent UIView canvas surface.
                dotGridCanvas
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // LAYER 1 — Canvas touch surface (transparent background so the dot
                // grid shows through). Deadzones carve out sidebar + HUD hit areas.
                CanvasRepresentable(sink: viewModel, deadzones: deadzones)
                    .ignoresSafeArea()

                // LAYER 2 — Express Keys sidebar (left or right edge). Hidden in fullscreen.
                if !isFullscreen {
                    sidebarOverlay(fullGeo: fullGeo)
                }

                // LAYER 3 — HUD controls (top corners).
                hudOverlay(fullGeo: fullGeo)

                // LAYER 4 — Click flash overlay (K.2). Non-interactive.
                clickFlashOverlay
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .bottom)
        .sheet(isPresented: $showSettings) {
            // Bug 1 fix: wrap in a single NavigationStack at the call site.
            // ExpressKeysSettingsScreen and EditKeySheet each declare their own
            // NavigationStack internally — remove the outer one here and let the
            // outermost one in ExpressKeysSettingsScreen own navigation.
            ExpressKeysSettingsScreen(store: profileStore, settingsRepo: settingsRepo)
        }
    }

    // MARK: - Dot grid (visual parity with Android CaptureSurface)

    /// Subtle dot grid at 24 pt pitch on a near-black background, matching Android's
    /// `drawDotGrid` (32 dp pitch adapted to iOS point units).
    ///
    /// Dot color brightens when connected, matching Android:
    ///   • Connected:    #3F3F3F (`Color.inkDotBright`)
    ///   • Disconnected: #262626 (`Color.inkDotDim`)
    private var dotGridCanvas: some View {
        let isConnected: Bool = {
            if case .connected = viewModel.connectionState { return true }
            return false
        }()
        let dotColor = isConnected ? Color.inkDotBright : Color.inkDotDim

        return Canvas { context, size in
            let spacing: CGFloat = 24
            let radius: CGFloat = 1
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x - radius, y: y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(dotColor)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
        .background(Color.inkBlack)
        .animation(.easeInOut(duration: 0.4), value: isConnected)
    }

    // MARK: - Click Flash Overlay (K.2)

    @ViewBuilder
    private var clickFlashOverlay: some View {
        GeometryReader { geo in
            let _ = geo // suppress unused-variable warning
            switch viewModel.clickFlash {
            case .idle:
                EmptyView()
            case .left(let pt):
                clickCircle(at: pt, color: .white)
            case .right(let pt):
                // Right-click uses the InkBridge accent cyan (matches Android).
                clickCircle(at: pt, color: .inkAccent)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func clickCircle(at point: CGPoint, color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.6))
            .frame(width: 40, height: 40)
            .position(point)
            .animation(.easeOut(duration: 0.08), value: viewModel.clickFlash)
    }

    // MARK: - Sidebar

    /// Renders the sidebar and reports its frame as a deadzone so the canvas
    /// UIView does NOT consume touches that belong to sidebar buttons.
    @ViewBuilder
    private func sidebarOverlay(fullGeo: GeometryProxy) -> some View {
        let profile = viewModel.activeProfile
        let edge = viewModel.sidebarEdge

        let hapticIntensity = settingsRepo.hapticIntensity

        if edge == .leading {
            HStack(spacing: 0) {
                ExpressKeysSidebar(
                    profile: profile,
                    edge: edge,
                    hapticIntensity: hapticIntensity,
                    onKeyEvent: { event in
                        viewModel.handleExpressKeyEvent(event)
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            updateDeadzone(id: 0, rect: geo.frame(in: .global))
                        }.onChange(of: geo.frame(in: .global)) { _, rect in
                            updateDeadzone(id: 0, rect: rect)
                        }
                    }
                )
                Spacer()
            }
            .ignoresSafeArea()
        } else {
            HStack(spacing: 0) {
                Spacer()
                ExpressKeysSidebar(
                    profile: profile,
                    edge: edge,
                    hapticIntensity: hapticIntensity,
                    onKeyEvent: { event in
                        viewModel.handleExpressKeyEvent(event)
                    }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            updateDeadzone(id: 0, rect: geo.frame(in: .global))
                        }.onChange(of: geo.frame(in: .global)) { _, rect in
                            updateDeadzone(id: 0, rect: rect)
                        }
                    }
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - HUD

    /// Renders the HUD button row and reports its frame as a deadzone.
    ///
    /// In fullscreen mode, only the fullscreen-toggle button remains visible
    /// (small, semi-transparent) so the user can exit fullscreen. All other
    /// HUD elements (pill, settings, disconnect) fade out.
    @ViewBuilder
    private func hudOverlay(fullGeo: GeometryProxy) -> some View {
        VStack {
            HStack {
                // Top-left: connection-state pill (non-interactive, no deadzone needed).
                // Hidden in fullscreen.
                ConnectionStatePill(state: viewModel.connectionState)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.connectionState)
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
                    .opacity(isFullscreen ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isFullscreen)

                Spacer()

                // Top-right: settings + disconnect + fullscreen-toggle buttons.
                HStack(spacing: 12) {
                    // Settings and disconnect — hidden in fullscreen.
                    Group {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }

                        Button(action: { onDisconnect() }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .opacity(isFullscreen ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isFullscreen)

                    // Fullscreen toggle — always visible (semi-transparent in fullscreen).
                    Button(action: { isFullscreen.toggle() }) {
                        Image(systemName: isFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white.opacity(isFullscreen ? 0.45 : 0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .animation(.easeInOut(duration: 0.3), value: isFullscreen)
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            updateDeadzone(id: 1, rect: geo.frame(in: .global))
                        }.onChange(of: geo.frame(in: .global)) { _, rect in
                            updateDeadzone(id: 1, rect: rect)
                        }
                    }
                )
            }
            Spacer()
        }
    }

    // MARK: - Deadzone management

    /// Stores a deadzone by slot index (0 = sidebar, 1 = HUD buttons).
    /// Grows the array as needed.
    private func updateDeadzone(id: Int, rect: CGRect) {
        if deadzones.count <= id {
            deadzones.append(contentsOf: Array(repeating: .zero, count: id - deadzones.count + 1))
        }
        deadzones[id] = rect
    }
}

// MARK: - ConnectionStatePill

/// Compact indicator showing the current connection state.
///
/// When connected, a pulsing halo animates behind the dot at a 1.2 s loop,
/// scaling from 1× to 2× and fading out — matching Android StatusScreen pulse.
private struct ConnectionStatePill: View {
    let state: ConnectionState

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    private var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                // Pulsing halo — only visible when connected.
                if isConnected {
                    Circle()
                        .fill(Color.inkAccent)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }

                // Solid dot.
                Circle()
                    .fill(pillColor)
                    .frame(width: 8, height: 8)
            }

            Text(pillLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .onAppear {
            if isConnected { startPulse() }
        }
        .onChange(of: isConnected) { _, connected in
            if connected {
                startPulse()
            } else {
                stopPulse()
            }
        }
    }

    // MARK: - Pulse helpers

    private func startPulse() {
        pulseScale = 1.0
        pulseOpacity = 0.8
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            pulseScale = 2.0
            pulseOpacity = 0.0
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: 0.2)) {
            pulseScale = 1.0
            pulseOpacity = 0.0
        }
    }

    // MARK: - State helpers

    private var pillColor: Color {
        switch state {
        case .idle:          return .gray
        case .connecting:    return .yellow
        case .connected:     return .inkAccent
        case .failed:        return .red
        }
    }

    private var pillLabel: String {
        switch state {
        case .idle:               return "idle"
        case .connecting:         return "connecting…"
        case .connected(let h):   return "\(h.name) \(h.ipv4):\(h.port)"
        case .failed(let r):      return "error: \(r)"
        }
    }
}
