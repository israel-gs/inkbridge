package com.inkbridge.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusTarget
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.inkbridge.domain.model.ExpressKey
import com.inkbridge.domain.model.ExpressKeyAction
import com.inkbridge.domain.model.ExpressKeyProfile
import com.inkbridge.domain.model.or
import com.inkbridge.protocol.KeyAction
import com.inkbridge.protocol.KeyComboLabel
import com.inkbridge.protocol.KeyModifier
import com.inkbridge.protocol.MacKeyCodes

private val Cyan = Color(0xFF00C8FF)

/**
 * The profile + edit-keys block that lives inside the Express Keys section
 * of the settings sheet. Renders:
 *   - "Profile [Default ⌄]" dropdown row
 *   - "Edit keys" button below the dropdown
 *
 * Owns all dialogs needed to create/rename/delete profiles and edit slots.
 */
@Composable
fun ExpressKeyProfileSection(
    profiles: List<ExpressKeyProfile>,
    activeProfileId: String,
    onSelectProfile: (String) -> Unit,
    onCreateProfile: (String) -> Unit,
    onRenameProfile: (String, String) -> Unit,
    onDeleteProfile: (String) -> Unit,
    onUpdateSlot: (Int, ExpressKeyAction, String) -> Unit,
    onRequestMacCapture: suspend (UByte) -> Pair<UByte, UByte>? = { null },
) {
    val active = profiles.firstOrNull { it.id == activeProfileId } ?: profiles.firstOrNull()
    var dropdownOpen by remember { mutableStateOf(false) }
    var creating by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<ExpressKeyProfile?>(null) }
    var deleting by remember { mutableStateOf<ExpressKeyProfile?>(null) }
    var editingKeys by remember { mutableStateOf(false) }
    var editingSlot by remember { mutableStateOf<ExpressKey?>(null) }

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
        ) {
            Text(
                text = "Profile",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Box {
                Surface(
                    onClick = { dropdownOpen = true },
                    shape = RoundedCornerShape(20.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant,
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.padding(start = 14.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
                    ) {
                        Text(
                            text = active?.name ?: "—",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                        Spacer(Modifier.width(4.dp))
                        Icon(
                            imageVector = Icons.Outlined.ExpandMore,
                            contentDescription = "Choose profile",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                DropdownMenu(
                    expanded = dropdownOpen,
                    onDismissRequest = { dropdownOpen = false },
                ) {
                    profiles.forEach { profile ->
                        DropdownMenuItem(
                            text = {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        text = profile.name,
                                        color = if (profile.id == activeProfileId) Cyan
                                                else MaterialTheme.colorScheme.onSurface,
                                        fontWeight = if (profile.id == activeProfileId) FontWeight.SemiBold
                                                     else FontWeight.Normal,
                                    )
                                    Spacer(Modifier.width(12.dp))
                                    IconButton(onClick = {
                                        dropdownOpen = false
                                        renaming = profile
                                    }, modifier = Modifier.size(32.dp)) {
                                        Icon(Icons.Outlined.MoreHoriz, contentDescription = "More")
                                    }
                                }
                            },
                            onClick = {
                                onSelectProfile(profile.id)
                                dropdownOpen = false
                            },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        leadingIcon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                        text = { Text("New profile…") },
                        onClick = {
                            dropdownOpen = false
                            creating = true
                        },
                    )
                }
            }
        }

        TextButton(
            onClick = { editingKeys = true },
            modifier = Modifier.padding(start = 4.dp),
        ) {
            Text("Edit keys for \"${active?.name ?: "—"}\"")
            Icon(Icons.Outlined.ChevronRight, contentDescription = null)
        }
    }

    // --- Dialogs ---

    if (creating) {
        ProfileNameDialog(
            title = "New profile",
            initial = "",
            onConfirm = { name ->
                if (name.isNotBlank()) onCreateProfile(name.trim())
                creating = false
            },
            onCancel = { creating = false },
        )
    }

    renaming?.let { profile ->
        ProfileMoreDialog(
            profile = profile,
            canDelete = profiles.size > 1,
            onRename = { newName ->
                if (newName.isNotBlank() && newName != profile.name) {
                    onRenameProfile(profile.id, newName.trim())
                }
                renaming = null
            },
            onDelete = {
                renaming = null
                deleting = profile
            },
            onCancel = { renaming = null },
        )
    }

    deleting?.let { profile ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text("Delete \"${profile.name}\"?") },
            text = { Text("This profile and its key bindings will be removed.") },
            confirmButton = {
                TextButton(onClick = {
                    onDeleteProfile(profile.id)
                    deleting = null
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { deleting = null }) { Text("Cancel") }
            },
        )
    }

    if (editingKeys && active != null) {
        Dialog(onDismissRequest = { editingKeys = false }) {
            KeyListSheet(
                profile = active,
                onClose = { editingKeys = false },
                onSlot = { editingSlot = it },
            )
        }
    }

    editingSlot?.let { slot ->
        Dialog(onDismissRequest = { editingSlot = null }) {
            SlotEditorSheet(
                initial = slot,
                onSave = { action, label ->
                    onUpdateSlot(slot.id, action, label)
                    editingSlot = null
                },
                onCancel = { editingSlot = null },
                onRequestMacCapture = onRequestMacCapture,
            )
        }
    }
}

// ── Profile name dialog (used for create) ────────────────────────────────────

@Composable
private fun ProfileNameDialog(
    title: String,
    initial: String,
    onConfirm: (String) -> Unit,
    onCancel: () -> Unit,
) {
    var name by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                singleLine = true,
                placeholder = { Text("Profile name") },
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name) },
                enabled = name.isNotBlank(),
            ) { Text("Create") }
        },
        dismissButton = {
            TextButton(onClick = onCancel) { Text("Cancel") }
        },
    )
}

// ── Profile rename + delete dialog ───────────────────────────────────────────

@Composable
private fun ProfileMoreDialog(
    profile: ExpressKeyProfile,
    canDelete: Boolean,
    onRename: (String) -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
) {
    var name by remember(profile.id) { mutableStateOf(profile.name) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("Edit profile") },
        text = {
            Column {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    singleLine = true,
                    placeholder = { Text("Profile name") },
                )
                if (canDelete) {
                    Spacer(Modifier.height(12.dp))
                    TextButton(onClick = onDelete) {
                        Text("Delete profile", color = MaterialTheme.colorScheme.error)
                    }
                } else {
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = "Cannot delete the last remaining profile.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onRename(name) },
                enabled = name.isNotBlank(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = onCancel) { Text("Cancel") }
        },
    )
}

// ── Key list sheet (6 slots) ─────────────────────────────────────────────────

@Composable
private fun KeyListSheet(
    profile: ExpressKeyProfile,
    onClose: () -> Unit,
    onSlot: (ExpressKey) -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
                .heightIn(max = 600.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = profile.name,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onClose) { Text("Done") }
            }
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                profile.keys.forEach { key ->
                    KeyListRow(key = key, onClick = { onSlot(key) })
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun KeyListRow(key: ExpressKey, onClick: () -> Unit) {
    val summary = when (val a = key.action) {
        is ExpressKeyAction.Shortcut -> KeyComboLabel.forShortcut(a.keyCode, a.modifiers)
        is ExpressKeyAction.ModifierHold -> KeyComboLabel.forHold(a.keyCode, a.modifiers)
    }
    Surface(
        onClick = onClick,
        color = Color.Transparent,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(vertical = 12.dp, horizontal = 4.dp),
        ) {
            Text(
                text = key.id.toString(),
                modifier = Modifier.width(24.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelMedium,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = key.label,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = summary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontFamily = FontFamily.Monospace,
                )
            }
            Icon(
                Icons.Outlined.ChevronRight,
                contentDescription = "Edit",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Slot editor (key capture + label) ────────────────────────────────────────

@Composable
private fun SlotEditorSheet(
    initial: ExpressKey,
    onSave: (ExpressKeyAction, String) -> Unit,
    onCancel: () -> Unit,
    onRequestMacCapture: suspend (UByte) -> Pair<UByte, UByte>? = { null },
) {
    val initialAction = initial.action
    var isHold by remember(initial.id) { mutableStateOf(initialAction is ExpressKeyAction.ModifierHold) }
    var keyCode by remember(initial.id) {
        mutableStateOf(when (initialAction) {
            is ExpressKeyAction.Shortcut -> initialAction.keyCode
            is ExpressKeyAction.ModifierHold -> initialAction.keyCode
        })
    }
    var modifiers by remember(initial.id) {
        mutableStateOf(when (initialAction) {
            is ExpressKeyAction.Shortcut -> initialAction.modifiers
            is ExpressKeyAction.ModifierHold -> initialAction.modifiers
        })
    }
    var label by remember(initial.id) { mutableStateOf(initial.label) }
    var lastAutoLabel by remember(initial.id) {
        mutableStateOf(
            when (initialAction) {
                is ExpressKeyAction.Shortcut -> KeyComboLabel.forShortcut(initialAction.keyCode, initialAction.modifiers)
                is ExpressKeyAction.ModifierHold -> KeyComboLabel.forHold(initialAction.keyCode, initialAction.modifiers)
            }
        )
    }

    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
        ) {
            Text(
                text = "Slot ${initial.id}",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(16.dp))

            // Type segmented
            Text(
                text = "Type",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                EdgeChip(
                    label = "Shortcut",
                    selected = !isHold,
                    onClick = {
                        isHold = false
                        // When switching to Shortcut, retain modifiers but clear key only if it was 0.
                    },
                )
                EdgeChip(
                    label = "Hold",
                    selected = isHold,
                    onClick = {
                        isHold = true
                        // Hold can be modifier-only — keyCode 0 is valid.
                    },
                )
            }
            Spacer(Modifier.height(20.dp))

            if (!isHold) {
                Text(
                    text = "Key",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(6.dp))
                KeyCaptureBox(
                    keyCode = keyCode,
                    modifiers = modifiers,
                    onCaptured = { newKeyCode, newMods ->
                        keyCode = newKeyCode
                        modifiers = newMods
                        val nextAuto = KeyComboLabel.forShortcut(newKeyCode, newMods)
                        if (label == lastAutoLabel || label.isBlank()) {
                            label = nextAuto
                        }
                        lastAutoLabel = nextAuto
                    },
                    onClear = {
                        keyCode = 0u
                        modifiers = 0u
                    },
                )
                Spacer(Modifier.height(8.dp))
                MacCaptureButton(
                    slotId = initial.id.toUByte(),
                    onRequestMacCapture = onRequestMacCapture,
                    onCaptured = { newKeyCode, newMods ->
                        keyCode = newKeyCode
                        modifiers = newMods
                        val nextAuto = KeyComboLabel.forShortcut(newKeyCode, newMods)
                        if (label == lastAutoLabel || label.isBlank()) {
                            label = nextAuto
                        }
                        lastAutoLabel = nextAuto
                    },
                )
            } else {
                Text(
                    text = "Modifiers",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(6.dp))
                ModifierChips(
                    modifiers = modifiers,
                    onChange = { newMods ->
                        modifiers = newMods
                        val nextAuto = KeyComboLabel.forHold(keyCode, newMods)
                        if (label == lastAutoLabel || label.isBlank()) {
                            label = nextAuto
                        }
                        lastAutoLabel = nextAuto
                    },
                )
            }

            Spacer(Modifier.height(20.dp))

            // Label field
            Text(
                text = "Label",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = label,
                onValueChange = { label = it },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("e.g. Undo") },
            )

            Spacer(Modifier.height(24.dp))

            val saveEnabled = when {
                label.isBlank() -> false
                isHold -> modifiers.toInt() != 0 || keyCode.toInt() != 0
                else -> keyCode.toInt() != 0
            }

            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        val newAction: ExpressKeyAction = if (isHold) {
                            ExpressKeyAction.ModifierHold(keyCode = keyCode, modifiers = modifiers)
                        } else {
                            ExpressKeyAction.Shortcut(keyCode = keyCode, modifiers = modifiers)
                        }
                        onSave(newAction, label.trim())
                    },
                    enabled = saveEnabled,
                ) { Text("Save") }
            }
        }
    }
}

@Composable
private fun KeyCaptureBox(
    keyCode: UByte,
    modifiers: UByte,
    onCaptured: (UByte, UByte) -> Unit,
    onClear: () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    var hasFocus by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    val captured = if (keyCode.toInt() != 0 || modifiers.toInt() != 0) {
        KeyComboLabel.forShortcut(keyCode, modifiers)
    } else null

    Column {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .fillMaxWidth()
                .height(72.dp)
                .background(
                    color = if (hasFocus) Cyan.copy(alpha = 0.08f)
                            else MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(12.dp),
                )
                .border(
                    width = 1.dp,
                    color = if (hasFocus) Cyan.copy(alpha = 0.5f) else Color.Transparent,
                    shape = RoundedCornerShape(12.dp),
                )
                .focusRequester(focusRequester)
                .onFocusChanged { hasFocus = it.isFocused }
                .focusTarget()
                .onKeyEvent { event ->
                    if (event.type == KeyEventType.KeyDown) {
                        val androidKeyCode = event.key.nativeKeyCode
                        // Filter out modifier-only keys.
                        if (MacKeyCodes.isModifierKey(androidKeyCode)) return@onKeyEvent false
                        val mac = MacKeyCodes.forAndroidKeyCode(androidKeyCode)
                        if (mac != null) {
                            var mods: UByte = 0u
                            if (event.isMetaPressed)  mods = mods.or(KeyModifier.CMD)
                            if (event.isCtrlPressed)  mods = mods.or(KeyModifier.CTRL)
                            if (event.isAltPressed)   mods = mods.or(KeyModifier.OPT)
                            if (event.isShiftPressed) mods = mods.or(KeyModifier.SHIFT)
                            onCaptured(mac, mods)
                            return@onKeyEvent true
                        }
                    }
                    false
                },
        ) {
            if (captured != null) {
                Text(
                    text = captured,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = if (hasFocus) Cyan else MaterialTheme.colorScheme.onSurface,
                )
            } else {
                Text(
                    text = if (hasFocus) "Press a key…" else "Tap to capture",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (captured != null) {
            Spacer(Modifier.height(6.dp))
            TextButton(onClick = onClear) { Text("Clear") }
        }
    }
}

/**
 * "Capture from Mac" button — when tapped, sends a CAPTURE_REQUEST over the
 * wire and suspends until the Mac returns a response (user pressed a key) or
 * cancels. While in flight, the button shows a spinner-y "Waiting for Mac…"
 * label so the user knows to look at the Mac.
 */
@Composable
private fun MacCaptureButton(
    slotId: UByte,
    onRequestMacCapture: suspend (UByte) -> Pair<UByte, UByte>?,
    onCaptured: (UByte, UByte) -> Unit,
) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var pending by remember { mutableStateOf(false) }
    var lastError by remember { mutableStateOf<String?>(null) }

    Column {
        TextButton(
            onClick = {
                if (pending) return@TextButton
                pending = true
                lastError = null
                scope.launch {
                    try {
                        val result = onRequestMacCapture(slotId)
                        if (result != null) {
                            onCaptured(result.first, result.second)
                        } else {
                            lastError = "Cancelled or timed out"
                        }
                    } catch (t: Throwable) {
                        lastError = t.message ?: "Capture failed"
                    } finally {
                        pending = false
                    }
                }
            },
            enabled = !pending,
        ) {
            Text(
                text = if (pending) "Waiting for Mac…" else "Capture from Mac",
                color = if (pending) MaterialTheme.colorScheme.onSurfaceVariant else Cyan,
            )
        }
        lastError?.let {
            Text(
                text = it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun ModifierChips(modifiers: UByte, onChange: (UByte) -> Unit) {
    val items = listOf(
        "⌘ Cmd" to KeyModifier.CMD,
        "⌃ Ctrl" to KeyModifier.CTRL,
        "⌥ Opt" to KeyModifier.OPT,
        "⇧ Shift" to KeyModifier.SHIFT,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { (label, bit) ->
            val on = (modifiers.toInt() and bit.toInt()) != 0
            EdgeChip(
                label = label,
                selected = on,
                onClick = {
                    val newBits = if (on) modifiers.toInt() and bit.toInt().inv()
                                  else modifiers.toInt() or bit.toInt()
                    onChange(newBits.toUByte())
                },
            )
        }
    }
}
