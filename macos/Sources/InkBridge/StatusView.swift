import SwiftUI
import Charts
import InkBridgeCore

/// Server status window displayed when Accessibility permission is granted.
///
/// Shows server state, transport mode, packet stats, and a help sheet
/// with the `adb reverse` command. ui.md R5, R9.
struct StatusView: View {

    @ObservedObject var viewModel: ServerViewModel
    @State private var showingHelp = false
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status pill
            statePill

            // USB tunnel state chip
            tunnelChip

            Divider()

            // Stats grid
            statsSection

            // Latency histogram (only mounted when toggle is on; when off the
            // Chart isn't created at all, so it consumes zero MainActor time).
            if viewModel.showLatencyChart {
                Divider()
                latencySection
            }

            Divider()

            // Footer
            HStack {
                Text("UDP (Wi-Fi) + TCP (USB loopback)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .help("Settings")
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingSettings) {
                    SettingsSheet(viewModel: viewModel)
                }

                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .help("USB setup help")
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingHelp) {
                    HelpSheet()
                }
            }

            // Start/Stop toggle — label and action follow serverState so the
            // user can restart after stopping without relaunching the app.
            Group {
                switch viewModel.serverState {
                case .listening, .degraded:
                    Button("Stop Server", role: .destructive) {
                        viewModel.stopServer()
                    }
                case .idle:
                    Button("Start Server") {
                        viewModel.startServer()
                    }
                }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 240)
    }

    // MARK: - Latency

    private var latencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text("Latency")
                    .font(.headline)
                Spacer()
                latencyMetric(label: "p50", ms: viewModel.latency.arrivalToInjectP50Ms)
                latencyMetric(label: "p95", ms: viewModel.latency.arrivalToInjectP95Ms)
                latencyMetric(label: "p99", ms: viewModel.latency.arrivalToInjectP99Ms)
            }

            if viewModel.latency.samples == 0 {
                Text("No samples yet — draw something to populate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                let bins = latencyHistogram(
                    samples: viewModel.latency.arrivalToInjectSamplesNs,
                    buckets: 12
                )
                Chart(bins, id: \.midpointMs) { bin in
                    BarMark(
                        x: .value("ms", bin.midpointMs),
                        y: .value("count", bin.count)
                    )
                    .foregroundStyle(.cyan)
                }
                .frame(height: 80)
                .chartYAxis(.hidden)
            }

            Text("Mac-internal arrival → inject latency. Cross-device clock skew not shown.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func latencyMetric(label: String, ms: Double) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", ms))
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Sub-views

    private var statePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pillColor)
                .frame(width: 10, height: 10)
            Text(pillLabel)
                .font(.headline)
            Spacer()
        }
    }

    private var pillColor: Color {
        switch viewModel.serverState {
        case .listening: return .green
        case .degraded:  return .yellow
        case .idle:      return .gray
        }
    }

    private var pillLabel: String {
        switch viewModel.serverState {
        case .listening(let port): return "Listening on :\(port)"
        case .degraded(let reason): return "Degraded — \(reason)"
        case .idle: return "Not listening"
        }
    }

    // MARK: - Tunnel chip

    private var tunnelChip: some View {
        HStack(spacing: 6) {
            Image(systemName: tunnelChipIcon)
                .foregroundStyle(tunnelChipColor)
            Text(tunnelChipLabel)
                .font(.body)
                .foregroundStyle(tunnelChipColor)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tunnelChipColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var tunnelChipIcon: String {
        switch viewModel.tunnelState {
        case .idle:           return "rectangle.connected.to.line.below"
        case .active:         return "checkmark.circle.fill"
        case .unavailable:    return "exclamationmark.triangle"
        }
    }

    private var tunnelChipColor: Color {
        switch viewModel.tunnelState {
        case .idle:        return .secondary
        case .active:      return .accentColor
        case .unavailable: return .orange
        }
    }

    private var tunnelChipLabel: String {
        switch viewModel.tunnelState {
        case .idle:
            return "USB: waiting for device"
        case .active(let count):
            return "USB: active (\(count) device\(count == 1 ? "" : "s"))"
        case .unavailable(let reason):
            return "USB: \(reason)"
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(label: "Packets received",   value: "\(viewModel.stats.packetsReceived)")
            statRow(label: "Packets dropped",    value: "\(viewModel.stats.packetsDropped)")
            statRow(label: "Injection failures", value: "\(viewModel.stats.injectionFailures)")
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Settings sheet

private struct SettingsSheet: View {
    @ObservedObject var viewModel: ServerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            Toggle(isOn: $viewModel.smoothingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Position smoothing")
                    Text("One-Euro filter on stylus X/Y. Reduces jitter in hover and at low pressure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $viewModel.showLatencyChart) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show latency chart")
                    Text("Live histogram of arrival → inject time (Mac-internal).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 380, height: 240)
    }
}

// MARK: - Help sheet

private struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let command = "adb reverse tcp:4545 tcp:4545"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("USB Setup")
                .font(.headline)

            Text("Run this command in your terminal with your Android device connected via USB:")
                .font(.body)

            HStack {
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy command")
            }

            Text("Then select USB (TCP) in the Android app and tap Connect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Previews

#Preview("Status — Listening Light") {
    StatusView(viewModel: PreviewServerViewModel.makeListening())
        .preferredColorScheme(.light)
}

#Preview("Status — Listening Dark") {
    StatusView(viewModel: PreviewServerViewModel.makeListening())
        .preferredColorScheme(.dark)
}

#Preview("Status — Degraded") {
    StatusView(viewModel: PreviewServerViewModel.makeDegraded())
}

#Preview("Status — USB Active") {
    StatusView(viewModel: PreviewServerViewModel.makeListeningWithTunnel(.active(deviceCount: 1)))
}

#Preview("Status — USB Idle") {
    StatusView(viewModel: PreviewServerViewModel.makeListeningWithTunnel(.idle))
}

#Preview("Status — USB Unavailable") {
    StatusView(viewModel: PreviewServerViewModel.makeListeningWithTunnel(.unavailable(reason: "adb not found")))
}
