import SwiftUI

// MARK: - EditKeySheet

/// Sheet for editing a single Express Key slot assignment.
///
/// # Segments
/// - **Preset**: picker over common shortcuts derived from the Android default set.
/// - **Custom**: free-form key code + modifier checkboxes + label field + hold-mode toggle.
///
/// # "Capture from Mac" button
/// Calls `viewModel.requestCapture(slot:)` — wired in Batch 6 (Block H / I).
/// For Batch 5, the button exists but its `requestCapture` stub is a no-op.
public struct EditKeySheet: View {

    // MARK: - Input

    let slotIndex: Int
    let onSave: (ExpressKey) -> Void

    // MARK: - Local state

    @State private var selectedTab: Tab = .preset
    @State private var draft: ExpressKey
    @State private var selectedPresetIndex: Int = 0
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable {
        case preset = "Preset"
        case custom = "Custom"
    }

    // MARK: - Preset list

    private static let presets: [(label: String, keyCode: UInt8, modifiers: UInt8, holdMode: HoldMode)] = [
        ("Ctrl (hold)", 0x00, ExpressKeyModifiers.ctrl, .modifierHold),
        ("Undo ⌘Z",    0x06, ExpressKeyModifiers.cmd,  .oneShot),
        ("Redo ⌘⇧Z",  0x06, ExpressKeyModifiers.cmd | ExpressKeyModifiers.shift, .oneShot),
        ("[ Brush −",  0x21, 0,                         .oneShot),
        ("] Brush +",  0x1E, 0,                         .oneShot),
        ("Space (hold)",0x31, 0,                         .modifierHold),
        ("⌘S Save",    0x01, ExpressKeyModifiers.cmd,  .oneShot),  // kVK_ANSI_S
        ("⌘C Copy",    0x08, ExpressKeyModifiers.cmd,  .oneShot),  // kVK_ANSI_C
        ("⌘V Paste",   0x09, ExpressKeyModifiers.cmd,  .oneShot),  // kVK_ANSI_V
        ("Shift (hold)",0x00, ExpressKeyModifiers.shift, .modifierHold),
    ]

    // MARK: - Init

    public init(key: ExpressKey, slotIndex: Int, onSave: @escaping (ExpressKey) -> Void) {
        self.slotIndex = slotIndex
        self.onSave = onSave
        _draft = State(initialValue: key)
    }

    // MARK: - Body

    public var body: some View {
        // Note: no NavigationStack here — EditKeySheet is always pushed as a
        // NavigationLink destination inside ExpressKeysSettingsScreen's NavigationStack.
        // A nested NavigationStack would break navigation and show an empty screen.
        VStack(spacing: 0) {
            // Segment control
            Picker("Mode", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .preset:
                    presetTab
                case .custom:
                    customTab
                }
            }

            Divider()

            // Capture from Mac (Batch 6 TODO)
            captureFromMacButton
                .padding()
        }
        .navigationTitle("Slot \(slotIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Preset tab

    @ViewBuilder
    private var presetTab: some View {
        List(Array(Self.presets.enumerated()), id: \.offset) { index, preset in
            HStack {
                VStack(alignment: .leading) {
                    Text(preset.label)
                    Text(preset.holdMode == .modifierHold ? "Hold" : "Tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedPresetIndex == index {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedPresetIndex = index
                draft = ExpressKey(
                    id: draft.id,
                    label: preset.label,
                    keyCode: preset.keyCode,
                    modifiers: preset.modifiers,
                    holdMode: preset.holdMode
                )
            }
        }
    }

    // MARK: - Custom tab

    @ViewBuilder
    private var customTab: some View {
        Form {
            Section("Label") {
                TextField("Short label (e.g. Undo)", text: $draft.label)
            }

            Section("Key Code") {
                HStack {
                    Text("macOS virtual key code")
                    Spacer()
                    TextField("Hex", text: Binding(
                        get: { String(format: "0x%02X", draft.keyCode) },
                        set: { str in
                            let clean = str.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "0X", with: "")
                            if let val = UInt8(clean, radix: 16) {
                                draft.keyCode = val
                            }
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.asciiCapable)
                }
            }

            Section("Modifiers") {
                Toggle("⌘ Command", isOn: modifierBinding(ExpressKeyModifiers.cmd))
                Toggle("⇧ Shift",   isOn: modifierBinding(ExpressKeyModifiers.shift))
                Toggle("⌃ Control", isOn: modifierBinding(ExpressKeyModifiers.ctrl))
                Toggle("⌥ Option",  isOn: modifierBinding(ExpressKeyModifiers.alt))
            }

            Section("Behavior") {
                Picker("Mode", selection: $draft.holdMode) {
                    Text("Tap (one-shot)").tag(HoldMode.oneShot)
                    Text("Hold (modifier)").tag(HoldMode.modifierHold)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Capture from Mac

    @ViewBuilder
    private var captureFromMacButton: some View {
        Button(action: {
            // TODO (Batch 6 H.4): call viewModel.requestCapture(slot: slotIndex)
            // CaptureFromMacModal will open and handle the round-trip.
        }) {
            Label("Capture from Mac", systemImage: "keyboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: - Modifier binding helper

    private func modifierBinding(_ bit: UInt8) -> Binding<Bool> {
        Binding(
            get: { draft.modifiers & bit != 0 },
            set: { on in
                if on {
                    draft.modifiers |= bit
                } else {
                    draft.modifiers &= ~bit
                }
            }
        )
    }
}
