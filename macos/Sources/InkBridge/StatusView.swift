import SwiftUI
import InkBridgeCore

/// Server status window displayed when Accessibility permission is granted.
///
/// Shows server state, transport mode, packet stats, and a help sheet
/// with the `adb reverse` command. ui.md R5, R9.
struct StatusView: View {

    @ObservedObject var viewModel: ServerViewModel
    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status pill
            statePill

            // USB tunnel state chip
            tunnelChip

            Divider()

            // Stats grid
            statsSection

            Divider()

            // Footer
            HStack {
                Text("UDP (Wi-Fi) + TCP (USB loopback)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

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
