import SwiftUI
import AppKit

/// Modal view shown on the Mac when the tablet asks to capture a key combo
/// for an express-key slot. Installs an `NSEvent` local monitor that
/// intercepts the next physical `keyDown`, packages the virtual keycode +
/// modifier flags, and reports them via `onSubmit`. `onCancel` fires when
/// the user closes the sheet without pressing a key (Esc).
///
/// Why a local monitor and not a SwiftUI `onKeyPress` handler: SwiftUI's
/// key-press support (macOS 14+) requires a focusable view that owns the
/// keyboard; getting that through a sheet is fiddly. `NSEvent
/// addLocalMonitorForEvents` is process-wide for the active window and
/// returns `nil` from the closure to swallow the event so the keystroke
/// does not leak to the underlying server window.
struct CaptureKeyView: View {

    let slotId: UInt8
    let onSubmit: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?
    @State private var capturedSummary: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture key for slot \(slotId)")
                .font(.headline)

            Text("Press the key combination on this Mac's keyboard. Esc to cancel.")
                .font(.body)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.cyan.opacity(0.06))
                    .frame(height: 80)

                if let summary = capturedSummary {
                    Text(summary)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(Color.cyan)
                } else {
                    Text("Waiting for keystroke…")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    cancel()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { installMonitor() }
        .onDisappear { removeMonitor() }
    }

    private func installMonitor() {
        // .keyDown for character keys; `.flagsChanged` is intentionally NOT
        // observed alone — bare modifier presses are not valid shortcuts.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc at any time → cancel without submitting.
            if event.keyCode == 53 { // kVK_Escape = 0x35 = 53
                cancel()
                return nil
            }
            capturedSummary = describe(event: event)
            // Brief visual flash before submitting so the user sees what was
            // captured. submit() removes the monitor + dismisses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                submit(event: event)
            }
            return nil // swallow the event so it does not reach the focused window
        }
    }

    private func removeMonitor() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    private func submit(event: NSEvent) {
        removeMonitor()
        onSubmit(event.keyCode, event.modifierFlags)
        dismiss()
    }

    private func cancel() {
        removeMonitor()
        onCancel()
        dismiss()
    }

    /// Pretty-prints the captured combo using Mac glyphs for display only.
    /// The wire format uses raw bitfield + virtual keycode separately.
    private func describe(event: NSEvent) -> String {
        var sb = ""
        let m = event.modifierFlags
        if m.contains(.control)  { sb += "⌃" }
        if m.contains(.option)   { sb += "⌥" }
        if m.contains(.shift)    { sb += "⇧" }
        if m.contains(.command)  { sb += "⌘" }
        let keyName = Self.keyName(forVirtualKey: event.keyCode)
        return sb.isEmpty ? keyName : "\(sb) \(keyName)"
    }

    private static func keyName(forVirtualKey vk: UInt16) -> String {
        switch vk {
        case 0x00: return "A"; case 0x01: return "S"; case 0x02: return "D"
        case 0x03: return "F"; case 0x04: return "H"; case 0x05: return "G"
        case 0x06: return "Z"; case 0x07: return "X"; case 0x08: return "C"
        case 0x09: return "V"; case 0x0B: return "B"; case 0x0C: return "Q"
        case 0x0D: return "W"; case 0x0E: return "E"; case 0x0F: return "R"
        case 0x10: return "Y"; case 0x11: return "T"; case 0x1F: return "O"
        case 0x20: return "U"; case 0x22: return "I"; case 0x23: return "P"
        case 0x25: return "L"; case 0x26: return "J"; case 0x28: return "K"
        case 0x2D: return "N"; case 0x2E: return "M"
        case 0x12: return "1"; case 0x13: return "2"; case 0x14: return "3"
        case 0x15: return "4"; case 0x16: return "6"; case 0x17: return "5"
        case 0x19: return "9"; case 0x1A: return "7"; case 0x1C: return "8"
        case 0x1D: return "0"
        case 0x18: return "="; case 0x1B: return "-"
        case 0x1E: return "]"; case 0x21: return "["; case 0x27: return "'"
        case 0x29: return ";"; case 0x2A: return "\\"; case 0x2B: return ","
        case 0x2C: return "/"; case 0x2F: return "."; case 0x32: return "`"
        case 0x24: return "Enter"; case 0x30: return "Tab"; case 0x31: return "Space"
        case 0x33: return "⌫"; case 0x75: return "⌦"; case 0x35: return "Esc"
        case 0x7B: return "←"; case 0x7C: return "→"; case 0x7D: return "↓"; case 0x7E: return "↑"
        case 0x7A: return "F1"; case 0x78: return "F2"; case 0x63: return "F3"
        case 0x76: return "F4"; case 0x60: return "F5"; case 0x61: return "F6"
        case 0x62: return "F7"; case 0x64: return "F8"; case 0x65: return "F9"
        case 0x6D: return "F10"; case 0x67: return "F11"; case 0x6F: return "F12"
        default: return String(format: "0x%02X", vk)
        }
    }
}
