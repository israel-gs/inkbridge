package com.inkbridge.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

// InkBridge is always dark. No dynamic color — brand stays consistent across
// devices. No system-follow — this is a creative tool and users expect the
// canvas surface to be dark regardless of OS theme.

private val InkColorScheme = darkColorScheme(
    primary = InkPrimary,
    onPrimary = InkOnPrimary,
    primaryContainer = InkPrimaryContainer,
    onPrimaryContainer = InkOnPrimaryContainer,

    secondary = InkSecondary,
    onSecondary = InkOnSecondary,
    secondaryContainer = InkSecondaryContainer,
    onSecondaryContainer = InkOnSecondaryContainer,

    tertiary = InkTertiary,
    onTertiary = InkOnTertiary,
    tertiaryContainer = InkTertiaryContainer,
    onTertiaryContainer = InkOnTertiaryContainer,

    error = InkError,
    onError = InkOnError,
    errorContainer = InkErrorContainer,
    onErrorContainer = InkOnErrorContainer,

    background = InkBlack,
    onBackground = InkOnSurface,
    surface = InkSurface,
    onSurface = InkOnSurface,
    surfaceVariant = InkSurfaceVariant,
    onSurfaceVariant = InkOnSurfaceVariant,
    surfaceContainer = InkSurfaceContainer,
    surfaceContainerHigh = InkSurfaceContainerHigh,

    outline = InkOutline,
    outlineVariant = InkOutlineVariant,
)

@Composable
fun InkBridgeTheme(
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = InkColorScheme,
        typography = InkBridgeTypography,
        content = content,
    )
}
