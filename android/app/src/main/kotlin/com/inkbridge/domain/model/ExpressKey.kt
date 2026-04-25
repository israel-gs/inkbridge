package com.inkbridge.domain.model

import com.inkbridge.protocol.KeyAction
import com.inkbridge.protocol.KeyModifier

/**
 * Configuration for a single express-key slot on the Android canvas overlay.
 *
 * @property id    Stable identifier (1..N) for ordering.
 * @property label Short text shown under the icon. Auto-derived from [action]
 *                 when the user has not provided a custom label.
 * @property action What the key does when tapped or held.
 */
data class ExpressKey(
    val id: Int,
    val label: String,
    val action: ExpressKeyAction,
)

/**
 * The kind of input event an express key emits.
 */
sealed interface ExpressKeyAction {
    /**
     * Tap fires a press+release pair atomically. Best for momentary actions
     * like Cmd+Z (undo).
     */
    data class Shortcut(
        val keyCode: UByte,
        val modifiers: UByte = 0u,
    ) : ExpressKeyAction

    /**
     * The modifier (or key) is held for as long as the user keeps a finger on
     * the slot. Best for Ctrl-as-color-picker, Space-as-pan, Shift-as-constrain.
     *
     * `keyCode` is `0u` for modifier-only (the macOS receiver emits a
     * flagsChanged event in that case — wire-protocol.md R3).
     */
    data class ModifierHold(
        val keyCode: UByte = 0u,
        val modifiers: UByte,
    ) : ExpressKeyAction
}

/**
 * macOS virtual keycodes (kVK_ANSI_*) used by the default preset.
 * Source: HIToolbox/Events.h. Position-based, layout-independent for character keys.
 */
object MacVirtualKey {
    const val Z: UByte = 0x06u
    const val LEFT_BRACKET: UByte = 0x21u  // [
    const val RIGHT_BRACKET: UByte = 0x1Eu // ]
    const val SPACE: UByte = 0x31u
}

/**
 * The factory-default 6-slot configuration. Aligns with the SDD design:
 *   1: Ctrl-hold      2: Cmd+Z (Undo)   3: Cmd+Shift+Z (Redo)
 *   4: [  (Brush −)   5: ]  (Brush +)   6: Space-hold (Pan)
 */
val DefaultExpressKeys: List<ExpressKey> = listOf(
    ExpressKey(
        id = 1, label = "Ctrl",
        action = ExpressKeyAction.ModifierHold(modifiers = KeyModifier.CTRL),
    ),
    ExpressKey(
        id = 2, label = "Undo",
        action = ExpressKeyAction.Shortcut(keyCode = MacVirtualKey.Z, modifiers = KeyModifier.CMD),
    ),
    ExpressKey(
        id = 3, label = "Redo",
        action = ExpressKeyAction.Shortcut(
            keyCode = MacVirtualKey.Z,
            modifiers = (KeyModifier.CMD or KeyModifier.SHIFT),
        ),
    ),
    ExpressKey(
        id = 4, label = "Brush −",
        action = ExpressKeyAction.Shortcut(keyCode = MacVirtualKey.LEFT_BRACKET),
    ),
    ExpressKey(
        id = 5, label = "Brush +",
        action = ExpressKeyAction.Shortcut(keyCode = MacVirtualKey.RIGHT_BRACKET),
    ),
    ExpressKey(
        id = 6, label = "Pan",
        action = ExpressKeyAction.ModifierHold(keyCode = MacVirtualKey.SPACE, modifiers = 0u),
    ),
)

/** Which side of the canvas the express-key bar lives on. */
enum class ExpressKeysEdge {
    LEFT, RIGHT;
}

/**
 * A user-named bundle of 6 express keys. The user can have any number of
 * profiles and switch between them manually from settings (e.g. "Default",
 * "Krita", "Excalidraw").
 *
 * @property id    Stable UUID — never reused. Persisted across renames.
 * @property name  Human-readable label shown in the picker.
 * @property keys  Exactly 6 entries; the bar always renders 6 slots.
 */
data class ExpressKeyProfile(
    val id: String,
    val name: String,
    val keys: List<ExpressKey>,
) {
    companion object {
        const val SLOT_COUNT = 6
    }

    init {
        require(keys.size == SLOT_COUNT) { "ExpressKeyProfile must have exactly $SLOT_COUNT keys, got ${keys.size}" }
    }
}

infix fun UByte.or(other: UByte): UByte = (this.toInt() or other.toInt()).toUByte()
