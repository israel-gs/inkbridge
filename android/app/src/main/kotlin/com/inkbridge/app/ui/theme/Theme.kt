package com.inkbridge.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import com.inkbridge.ui.theme.InkIndigo10
import com.inkbridge.ui.theme.InkIndigo20
import com.inkbridge.ui.theme.InkIndigo30
import com.inkbridge.ui.theme.InkIndigo40
import com.inkbridge.ui.theme.InkIndigo80
import com.inkbridge.ui.theme.InkIndigo90
import com.inkbridge.ui.theme.InkIndigoError40
import com.inkbridge.ui.theme.InkIndigoError80
import com.inkbridge.ui.theme.InkIndigoError90
import com.inkbridge.ui.theme.InkIndigoNeutral10
import com.inkbridge.ui.theme.InkIndigoNeutral90
import com.inkbridge.ui.theme.InkIndigoNeutral99
import com.inkbridge.ui.theme.InkBridgeTypography

private val LightColorScheme = lightColorScheme(
    primary = InkIndigo40,
    onPrimary = InkIndigoNeutral99,
    primaryContainer = InkIndigo90,
    onPrimaryContainer = InkIndigo10,
    error = InkIndigoError40,
    onError = InkIndigoNeutral99,
    errorContainer = InkIndigoError90,
    onErrorContainer = InkIndigoError40,
    background = InkIndigoNeutral99,
    onBackground = InkIndigoNeutral10,
    surface = InkIndigoNeutral99,
    onSurface = InkIndigoNeutral10,
)

private val DarkColorScheme = darkColorScheme(
    primary = InkIndigo80,
    onPrimary = InkIndigo20,
    primaryContainer = InkIndigo30,
    onPrimaryContainer = InkIndigo90,
    error = InkIndigoError80,
    onError = InkIndigoError40,
    errorContainer = InkIndigoError40,
    onErrorContainer = InkIndigoError90,
    background = InkIndigoNeutral10,
    onBackground = InkIndigoNeutral90,
    surface = InkIndigoNeutral10,
    onSurface = InkIndigoNeutral90,
)

@Composable
fun InkBridgeTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = InkBridgeTypography,
        content = content,
    )
}
