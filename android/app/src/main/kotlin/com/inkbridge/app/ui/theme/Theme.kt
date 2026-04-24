package com.inkbridge.app.ui.theme

// Kept as an alias for backwards compatibility with existing imports.
// The real theme lives in com.inkbridge.ui.theme.
import androidx.compose.runtime.Composable
import com.inkbridge.ui.theme.InkBridgeTheme as CoreInkBridgeTheme

@Composable
fun InkBridgeTheme(
    @Suppress("UNUSED_PARAMETER") darkTheme: Boolean = true,
    @Suppress("UNUSED_PARAMETER") dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    // darkTheme + dynamicColor params are ignored — InkBridge is always dark
    // with a fixed brand palette. Signature retained so existing @Preview
    // functions continue to compile.
    CoreInkBridgeTheme(content = content)
}
