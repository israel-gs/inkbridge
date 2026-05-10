import SwiftUI

// MARK: - ConnectionScreen

/// The connection screen shown when the app is not yet connected to a Mac server.
///
/// # Layout
/// - Top section: discovered hosts list. Tap a row to connect instantly.
/// - Bottom section: manual IP form (host + port) with a "Connect" button.
/// - Permission-denied banner: shown when `viewModel.connectionState == .failed`
///   with a "Local network" reason; includes a "Open Settings" button.
///
/// # Notes
/// - Wi-Fi only. USB is out of scope for iOS (spec §Out of scope).
/// - Discovery must be started externally (e.g. in `.onAppear`) by calling
///   `viewModel.startDiscovery()`.
public struct ConnectionScreen: View {

    @State var viewModel: ConnectionViewModel

    public init(viewModel: ConnectionViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Permission denied banner (shown above everything else)
                if case .failed(let reason) = viewModel.connectionState {
                    permissionBanner(reason: reason)
                }

                List {
                    // MARK: Discovered hosts
                    Section("Discovered Hosts") {
                        if viewModel.discoveredHosts.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Scanning for InkBridge servers…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(viewModel.discoveredHosts, id: \.ipv4) { host in
                                HostRow(host: host)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.connect(to: host)
                                    }
                            }
                        }
                    }

                    // MARK: Manual IP form
                    Section("Manual Connection") {
                        HStack {
                            Text("Host")
                                .foregroundStyle(.secondary)
                            TextField("IP or hostname", text: $viewModel.hostField)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        HStack {
                            Text("Port")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("4545", value: $viewModel.port, format: .number)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .frame(width: 80)
                        }

                        Button {
                            viewModel.connect()
                        } label: {
                            if case .connecting = viewModel.connectionState {
                                HStack {
                                    ProgressView()
                                    Text("Connecting…")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Connect")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            viewModel.hostField.trimmingCharacters(in: .whitespaces).isEmpty ||
                            viewModel.connectionState == .connecting
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("InkBridge")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.startDiscovery()
            }
            .onDisappear {
                viewModel.stopDiscovery()
            }
        }
    }

    // MARK: - Permission banner

    @ViewBuilder
    private func permissionBanner(reason: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Network Access Required")
                    .font(.subheadline).fontWeight(.semibold)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemOrange).opacity(0.12))
    }
}

// MARK: - HostRow

private struct HostRow: View {
    let host: DiscoveredHost

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(host.name)
                .font(.body)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                Text("\(host.ipv4):\(host.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(relativeLastSeen)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var relativeLastSeen: String {
        let secs = Date().timeIntervalSince(host.lastSeen)
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(Int(secs))s ago" }
        return "\(Int(secs / 60))m ago"
    }
}
