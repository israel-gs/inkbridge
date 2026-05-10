import Foundation

// MARK: - ExpressKeyPhase

/// The phase of an Express Key button interaction.
public enum ExpressKeyPhase {
    /// The user just pressed (touched down on) the Express Key button.
    case pressed
    /// The user just released (lifted off) the Express Key button.
    case released
}

// MARK: - ExpressKeyDispatcher

/// Stateless translator: converts an `ExpressKey` assignment and interaction
/// `phase` into a sequence of `StylusEvent` values to send to the Mac server.
///
/// # Mapping rules
///
/// | `holdMode`      | `phase`     | Emits                          |
/// |-----------------|-------------|--------------------------------|
/// | `.oneShot`      | `.pressed`  | `[.keyDown, .keyUp]`           |
/// | `.oneShot`      | `.released` | `[]`                           |
/// | `.modifierHold` | `.pressed`  | `[.keyDown]`                   |
/// | `.modifierHold` | `.released` | `[.keyUp]`                     |
/// | `nil` (unassigned slot) | any | `[]`                         |
///
/// One-shot keys emit DOWN+UP atomically on press so the Mac receives a
/// complete keystroke in a single packet. Modifier-hold keys emit DOWN on
/// press and UP on release so the modifier is held for the entire touch duration.
public enum ExpressKeyDispatcher {

    /// Returns the `StylusEvent` sequence for the given Express Key press or release.
    ///
    /// - Parameters:
    ///   - key: The key assignment for the slot, or `nil` if the slot is unassigned.
    ///   - phase: Whether the user is pressing or releasing the key.
    /// - Returns: An ordered array of `StylusEvent` values to transmit.
    public static func events(for key: ExpressKey?, phase: ExpressKeyPhase) -> [StylusEvent] {
        guard let key else { return [] }

        switch key.holdMode {
        case .oneShot:
            switch phase {
            case .pressed:
                // Emit press+release atomically so the server receives a
                // complete keystroke in a single UDP packet batch.
                return [
                    .keyEvent(keyCode: key.keyCode, modifiers: key.modifiers, action: .down),
                    .keyEvent(keyCode: key.keyCode, modifiers: key.modifiers, action: .up)
                ]
            case .released:
                // One-shot is self-contained on press; nothing to do on release.
                return []
            }

        case .modifierHold:
            switch phase {
            case .pressed:
                return [.keyEvent(keyCode: key.keyCode, modifiers: key.modifiers, action: .down)]
            case .released:
                return [.keyEvent(keyCode: key.keyCode, modifiers: key.modifiers, action: .up)]
            }
        }
    }
}
