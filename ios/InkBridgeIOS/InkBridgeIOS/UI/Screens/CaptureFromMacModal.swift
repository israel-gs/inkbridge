import SwiftUI

// MARK: - CaptureFromMacModal

/// Sheet presented from `EditKeySheet` when the user taps "Capture from Mac".
///
/// # Flow
/// 1. On appear: calls `viewModel.startCapture(slotId:)`.
/// 2. While `.requesting`: shows a spinner + "Press a key on your Mac to capture…"
/// 3. On `.captured`: calls `onCapture(keyCode:modifiers:)` and dismisses.
/// 4. On `.cancelled` or `.timeout`: shows an inline error or dismissal message.
/// 5. Cancel button: calls `viewModel.cancel()` and dismisses.
///
/// # 10-second timeout
/// If the Mac does not respond within 10 seconds, `viewModel.state` transitions
/// to `.timeout` and the modal shows "Mac did not respond. Try again."
public struct CaptureFromMacModal: View {

    @Environment(\.dismiss) private var dismiss

    let slotId: UInt8
    let onCapture: (_ keyCode: UInt8, _ modifiers: UInt8) -> Void
    @State var viewModel: CaptureFromMacViewModel

    public init(
        slotId: UInt8,
        viewModel: CaptureFromMacViewModel,
        onCapture: @escaping (_ keyCode: UInt8, _ modifiers: UInt8) -> Void
    ) {
        self.slotId = slotId
        self._viewModel = State(initialValue: viewModel)
        self.onCapture = onCapture
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                switch viewModel.state {
                case .idle, .requesting:
                    requestingView

                case .captured:
                    // Handled in onChange — dismiss immediately.
                    requestingView

                case .cancelled:
                    cancelledView

                case .timeout:
                    timeoutView

                case .error(let msg):
                    errorView(msg)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Capture from Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.startCapture(slotId: slotId)
            }
            .onChange(of: viewModel.state) { _, newState in
                if case .captured(let keyCode, let modifiers) = newState {
                    onCapture(keyCode, modifiers)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Sub-views

    private var requestingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Press a key on your Mac to capture…")
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Slot \(slotId + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cancelledView: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Cancelled")
                .font(.headline)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var timeoutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Mac did not respond. Try again.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Error")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
        }
    }
}
