package com.inkbridge.protocol

import android.view.KeyEvent

/**
 * Translation between Android [KeyEvent] keycodes and macOS Carbon-era
 * virtual keycodes (kVK_*). The mapping is position-based, not
 * character-based: macOS apps register shortcuts by virtual keycode
 * regardless of the active keyboard layout for letter/number keys.
 *
 * Source for kVK_* values: HIToolbox `Events.h`. ANSI keys covered.
 */
internal object MacKeyCodes {

    /** Android [KeyEvent] keyCode → macOS kVK_* virtual keycode. */
    private val MAP: Map<Int, UByte> = buildMap {
        // Letters
        put(KeyEvent.KEYCODE_A, 0x00u)
        put(KeyEvent.KEYCODE_S, 0x01u)
        put(KeyEvent.KEYCODE_D, 0x02u)
        put(KeyEvent.KEYCODE_F, 0x03u)
        put(KeyEvent.KEYCODE_H, 0x04u)
        put(KeyEvent.KEYCODE_G, 0x05u)
        put(KeyEvent.KEYCODE_Z, 0x06u)
        put(KeyEvent.KEYCODE_X, 0x07u)
        put(KeyEvent.KEYCODE_C, 0x08u)
        put(KeyEvent.KEYCODE_V, 0x09u)
        put(KeyEvent.KEYCODE_B, 0x0Bu)
        put(KeyEvent.KEYCODE_Q, 0x0Cu)
        put(KeyEvent.KEYCODE_W, 0x0Du)
        put(KeyEvent.KEYCODE_E, 0x0Eu)
        put(KeyEvent.KEYCODE_R, 0x0Fu)
        put(KeyEvent.KEYCODE_Y, 0x10u)
        put(KeyEvent.KEYCODE_T, 0x11u)
        put(KeyEvent.KEYCODE_O, 0x1Fu)
        put(KeyEvent.KEYCODE_U, 0x20u)
        put(KeyEvent.KEYCODE_I, 0x22u)
        put(KeyEvent.KEYCODE_P, 0x23u)
        put(KeyEvent.KEYCODE_L, 0x25u)
        put(KeyEvent.KEYCODE_J, 0x26u)
        put(KeyEvent.KEYCODE_K, 0x28u)
        put(KeyEvent.KEYCODE_N, 0x2Du)
        put(KeyEvent.KEYCODE_M, 0x2Eu)

        // Digits row
        put(KeyEvent.KEYCODE_1, 0x12u)
        put(KeyEvent.KEYCODE_2, 0x13u)
        put(KeyEvent.KEYCODE_3, 0x14u)
        put(KeyEvent.KEYCODE_4, 0x15u)
        put(KeyEvent.KEYCODE_6, 0x16u)
        put(KeyEvent.KEYCODE_5, 0x17u)
        put(KeyEvent.KEYCODE_EQUALS, 0x18u)
        put(KeyEvent.KEYCODE_9, 0x19u)
        put(KeyEvent.KEYCODE_7, 0x1Au)
        put(KeyEvent.KEYCODE_MINUS, 0x1Bu)
        put(KeyEvent.KEYCODE_8, 0x1Cu)
        put(KeyEvent.KEYCODE_0, 0x1Du)

        // Punctuation
        put(KeyEvent.KEYCODE_RIGHT_BRACKET, 0x1Eu)
        put(KeyEvent.KEYCODE_LEFT_BRACKET,  0x21u)
        put(KeyEvent.KEYCODE_APOSTROPHE,    0x27u)
        put(KeyEvent.KEYCODE_SEMICOLON,     0x29u)
        put(KeyEvent.KEYCODE_BACKSLASH,     0x2Au)
        put(KeyEvent.KEYCODE_COMMA,         0x2Bu)
        put(KeyEvent.KEYCODE_SLASH,         0x2Cu)
        put(KeyEvent.KEYCODE_PERIOD,        0x2Fu)
        put(KeyEvent.KEYCODE_GRAVE,         0x32u)

        // Whitespace / editing
        put(KeyEvent.KEYCODE_ENTER,     0x24u)
        put(KeyEvent.KEYCODE_TAB,       0x30u)
        put(KeyEvent.KEYCODE_SPACE,     0x31u)
        put(KeyEvent.KEYCODE_DEL,       0x33u) // Backspace on most keyboards
        put(KeyEvent.KEYCODE_FORWARD_DEL, 0x75u)
        put(KeyEvent.KEYCODE_ESCAPE,    0x35u)

        // Arrows
        put(KeyEvent.KEYCODE_DPAD_LEFT,  0x7Bu)
        put(KeyEvent.KEYCODE_DPAD_RIGHT, 0x7Cu)
        put(KeyEvent.KEYCODE_DPAD_DOWN,  0x7Du)
        put(KeyEvent.KEYCODE_DPAD_UP,    0x7Eu)

        // Function keys
        put(KeyEvent.KEYCODE_F1,  0x7Au)
        put(KeyEvent.KEYCODE_F2,  0x78u)
        put(KeyEvent.KEYCODE_F3,  0x63u)
        put(KeyEvent.KEYCODE_F4,  0x76u)
        put(KeyEvent.KEYCODE_F5,  0x60u)
        put(KeyEvent.KEYCODE_F6,  0x61u)
        put(KeyEvent.KEYCODE_F7,  0x62u)
        put(KeyEvent.KEYCODE_F8,  0x64u)
        put(KeyEvent.KEYCODE_F9,  0x65u)
        put(KeyEvent.KEYCODE_F10, 0x6Du)
        put(KeyEvent.KEYCODE_F11, 0x67u)
        put(KeyEvent.KEYCODE_F12, 0x6Fu)
    }

    /** Returns the macOS virtual keycode for an Android keyCode, or null if unsupported. */
    fun forAndroidKeyCode(androidKeyCode: Int): UByte? = MAP[androidKeyCode]

    /** True when [androidKeyCode] is a modifier key alone (no main key data). */
    fun isModifierKey(androidKeyCode: Int): Boolean = when (androidKeyCode) {
        KeyEvent.KEYCODE_SHIFT_LEFT,
        KeyEvent.KEYCODE_SHIFT_RIGHT,
        KeyEvent.KEYCODE_CTRL_LEFT,
        KeyEvent.KEYCODE_CTRL_RIGHT,
        KeyEvent.KEYCODE_ALT_LEFT,
        KeyEvent.KEYCODE_ALT_RIGHT,
        KeyEvent.KEYCODE_META_LEFT,
        KeyEvent.KEYCODE_META_RIGHT,
        KeyEvent.KEYCODE_FUNCTION,
        -> true
        else -> false
    }

    /** Translates Android `metaState` to the wire-format modifier bitfield. */
    fun modifiersFromMetaState(metaState: Int): UByte {
        var bits: UByte = 0u
        if ((metaState and KeyEvent.META_META_ON) != 0) bits = bits.or(KeyModifier.CMD)
        if ((metaState and KeyEvent.META_CTRL_ON) != 0) bits = bits.or(KeyModifier.CTRL)
        if ((metaState and KeyEvent.META_ALT_ON)  != 0) bits = bits.or(KeyModifier.OPT)
        if ((metaState and KeyEvent.META_SHIFT_ON) != 0) bits = bits.or(KeyModifier.SHIFT)
        return bits
    }
}

/**
 * Pretty-prints a key combo for display: "⌘⇧ Z", "⌃ Space", "[", etc.
 * Used to auto-fill the Label field in the editor and to render slot summaries.
 */
internal object KeyComboLabel {

    fun forShortcut(keyCode: UByte, modifiers: UByte): String {
        val mods = modifierGlyphs(modifiers)
        val keyName = keyName(keyCode)
        return if (mods.isEmpty()) keyName else "$mods $keyName"
    }

    fun forHold(keyCode: UByte, modifiers: UByte): String {
        val mods = modifierGlyphs(modifiers)
        val keyName = if (keyCode == 0u.toUByte()) "" else keyName(keyCode)
        val prefix = listOf(mods, keyName).filter { it.isNotEmpty() }.joinToString(" ")
        return if (prefix.isEmpty()) "—" else "$prefix hold"
    }

    fun modifierGlyphs(modifiers: UByte): String {
        val sb = StringBuilder()
        if ((modifiers and KeyModifier.CTRL).toInt()  != 0) sb.append("⌃")
        if ((modifiers and KeyModifier.OPT).toInt()   != 0) sb.append("⌥")
        if ((modifiers and KeyModifier.SHIFT).toInt() != 0) sb.append("⇧")
        if ((modifiers and KeyModifier.CMD).toInt()   != 0) sb.append("⌘")
        return sb.toString()
    }

    /** Inverse-lookup the macOS keycode to a printable name. */
    fun keyName(keyCode: UByte): String {
        return when (keyCode.toInt()) {
            // Letters (kVK_ANSI_A..Z etc.)
            0x00 -> "A"; 0x01 -> "S"; 0x02 -> "D"; 0x03 -> "F"; 0x04 -> "H"
            0x05 -> "G"; 0x06 -> "Z"; 0x07 -> "X"; 0x08 -> "C"; 0x09 -> "V"
            0x0B -> "B"; 0x0C -> "Q"; 0x0D -> "W"; 0x0E -> "E"; 0x0F -> "R"
            0x10 -> "Y"; 0x11 -> "T"; 0x1F -> "O"; 0x20 -> "U"; 0x22 -> "I"
            0x23 -> "P"; 0x25 -> "L"; 0x26 -> "J"; 0x28 -> "K"; 0x2D -> "N"
            0x2E -> "M"
            // Digits
            0x12 -> "1"; 0x13 -> "2"; 0x14 -> "3"; 0x15 -> "4"; 0x16 -> "6"
            0x17 -> "5"; 0x18 -> "="; 0x19 -> "9"; 0x1A -> "7"; 0x1B -> "-"
            0x1C -> "8"; 0x1D -> "0"
            // Punctuation
            0x1E -> "]"; 0x21 -> "["; 0x27 -> "'"; 0x29 -> ";"; 0x2A -> "\\"
            0x2B -> ","; 0x2C -> "/"; 0x2F -> "."; 0x32 -> "`"
            // Whitespace / editing
            0x24 -> "Enter"; 0x30 -> "Tab"; 0x31 -> "Space"; 0x33 -> "⌫"
            0x75 -> "⌦"; 0x35 -> "Esc"
            // Arrows
            0x7B -> "←"; 0x7C -> "→"; 0x7D -> "↓"; 0x7E -> "↑"
            // Function keys
            0x7A -> "F1"; 0x78 -> "F2"; 0x63 -> "F3"; 0x76 -> "F4"
            0x60 -> "F5"; 0x61 -> "F6"; 0x62 -> "F7"; 0x64 -> "F8"
            0x65 -> "F9"; 0x6D -> "F10"; 0x67 -> "F11"; 0x6F -> "F12"
            else -> "0x" + keyCode.toString(16).padStart(2, '0').uppercase()
        }
    }

    private infix fun UByte.and(other: UByte): UByte = (this.toInt() and other.toInt()).toUByte()
}
