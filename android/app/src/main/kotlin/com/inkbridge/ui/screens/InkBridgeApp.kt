package com.inkbridge.ui.screens

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.inkbridge.domain.model.ConnectionState

private const val ROUTE_CONNECTION = "connection"
private const val ROUTE_STATUS = "status"

/**
 * Root Compose function that owns navigation.
 *
 * Routes:
 * - "connection" — shown when Disconnected or Error.
 * - "status"     — shown when Connecting or Connected.
 *
 * The NavController navigates between routes automatically based on [ConnectionState].
 *
 * @param viewModel The single [ConnectionViewModel] shared across both screens.
 */
@Composable
fun InkBridgeApp(viewModel: ConnectionViewModel) {
    val navController = rememberNavController()
    val state by viewModel.connectionState.collectAsState()
    val stats by viewModel.stats.collectAsState()
    val naturalScroll by viewModel.naturalScroll.collectAsState()
    val autoReconnect by viewModel.autoReconnect.collectAsState()
    val isAutoReconnecting by viewModel.isAutoReconnecting.collectAsState()
    val hapticIntensity by viewModel.hapticIntensity.collectAsState()
    val clickFlashEnabled by viewModel.clickFlashEnabled.collectAsState()
    val expressKeysEnabled by viewModel.expressKeysEnabled.collectAsState()
    val expressKeysEdge by viewModel.expressKeysEdge.collectAsState()
    val expressKeys by viewModel.expressKeys.collectAsState()
    val profiles by viewModel.profiles.collectAsState()
    val activeProfileId by viewModel.activeProfileId.collectAsState()

    // Feature 3: wire haptic feedback.
    //
    // Many Samsung tablets (Tab S7 SM-T870 included) have a vibrator with
    // mSupportedEffects=[] — they cannot play VibrationEffect.EFFECT_CLICK or
    // any predefined effect. The View.performHapticFeedback path also fails on
    // these devices because internally it tries to use those effects. The only
    // thing that works is a raw createOneShot pulse.
    //
    // Strategy: skip View.performHapticFeedback entirely on devices where the
    // vibrator advertises no supported effects, and go straight to a raw 30ms
    // pulse with default amplitude. Use VibrationAttributes with USAGE_TOUCH
    // so the system applies the user's "Touch feedback intensity" preference.
    val view = LocalView.current
    val context = LocalContext.current
    val hapticImpl =
        remember(view, context) {
            // Resolve the system Vibrator once.
            val vibrator: Vibrator? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vm?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }

            // USAGE_TOUCH on Samsung tablets is scaled to 0 (verified via
            // dumpsys vibrator_manager — scale: 0,00 even when status: finished).
            // The user's tablet (SM-T870) has TOUCH=(LOW) intensity. We use
            // USAGE_COMMUNICATION_REQUEST which Samsung scales at HIGH and is
            // semantically appropriate for a synthetic click confirmation.
            val clickAttrs: android.os.VibrationAttributes? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    android.os.VibrationAttributes.Builder()
                        .setUsage(android.os.VibrationAttributes.USAGE_COMMUNICATION_REQUEST)
                        .build()
                } else {
                    null
                }

            HapticFeedback {
                // Read intensity from the VM at call-time so changes apply
                // immediately without requiring a recomposition + setHaptic.
                val intensity = viewModel.hapticIntensity.value
                if (intensity <= 0) return@HapticFeedback

                val v = vibrator ?: return@HapticFeedback

                // Many tablets (Tab S7 included) report mCapabilities=[] →
                // NO amplitude control. createOneShot's amplitude argument is
                // ignored. The only physical knobs we have are DURATION and
                // PULSE COUNT. We map intensity into both:
                //   1-30  → single short pulse (10–25ms).
                //   31-60 → single longer pulse (30–50ms).
                //   61-100 → double pulse with growing gap (stronger feel).
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = when {
                        intensity <= 30 -> {
                            val dur = 10L + (intensity * 15L / 30L) // 10..25ms
                            VibrationEffect.createOneShot(dur, VibrationEffect.DEFAULT_AMPLITUDE)
                        }
                        intensity <= 60 -> {
                            val dur = 30L + ((intensity - 30) * 20L / 30L) // 30..50ms
                            VibrationEffect.createOneShot(dur, VibrationEffect.DEFAULT_AMPLITUDE)
                        }
                        else -> {
                            // 61..100 → two pulses. Each pulse 35..55ms with a
                            // tight 25ms gap. Reads as a stronger, more deliberate
                            // confirmation than a single buzz.
                            val pulse = 35L + ((intensity - 60) * 20L / 40L) // 35..55ms
                            // pattern: wait 0, on pulse, off 25, on pulse
                            val pattern = longArrayOf(0L, pulse, 25L, pulse)
                            VibrationEffect.createWaveform(pattern, -1)
                        }
                    }
                    if (clickAttrs != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        v.vibrate(effect, clickAttrs)
                    } else {
                        v.vibrate(effect)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(40L)
                }
            }
        }
    // Propagate the View-backed haptic to the ViewModel (lazy injection after creation).
    viewModel.setHaptic(hapticImpl)

    NavHost(navController = navController, startDestination = ROUTE_CONNECTION) {
        composable(ROUTE_CONNECTION) {
            ConnectionScreen(
                state = state,
                onConnect = { host, port, kind ->
                    viewModel.connect(host, port, kind)
                    navController.navigate(ROUTE_STATUS) {
                        launchSingleTop = true
                    }
                },
                onDisconnect = {
                    viewModel.disconnect()
                },
            )
        }
        composable(ROUTE_STATUS) {
            StatusScreen(
                connectionState = state,
                stats = stats,
                onDisconnect = {
                    viewModel.disconnect()
                    navController.popBackStack()
                },
                onMotionEvent = { event, width, height ->
                    viewModel.onMotion(event, width, height)
                },
                onGestureEvent = { event, width, height, indices ->
                    viewModel.onGestureEvent(event, width, height, indices)
                },
                onTrackpadEvent = { event, width, height, indices ->
                    viewModel.onTrackpadEvent(event, width, height, indices)
                },
                naturalScroll = naturalScroll,
                onSetNaturalScroll = { viewModel.setNaturalScroll(it) },
                autoReconnect = autoReconnect,
                onSetAutoReconnect = { viewModel.setAutoReconnect(it) },
                isAutoReconnecting = isAutoReconnecting,
                hapticIntensity = hapticIntensity,
                onSetHapticIntensity = { viewModel.setHapticIntensity(it) },
                onPreviewHaptic = { hapticImpl.performTapFeedback() },
                clickFlashEnabled = clickFlashEnabled,
                onSetClickFlashEnabled = { viewModel.setClickFlashEnabled(it) },
                clickFlashes = viewModel.clickFlashes,
                expressKeysEnabled = expressKeysEnabled,
                onSetExpressKeysEnabled = { viewModel.setExpressKeysEnabled(it) },
                expressKeysEdge = expressKeysEdge,
                onSetExpressKeysEdge = { viewModel.setExpressKeysEdge(it) },
                expressKeys = expressKeys,
                onExpressKeyAction = { action, wireAction ->
                    viewModel.onExpressKey(action, wireAction)
                },
                profiles = profiles,
                activeProfileId = activeProfileId,
                onSelectProfile = { viewModel.setActiveProfile(it) },
                onCreateProfile = { name -> viewModel.createProfile(name) },
                onRenameProfile = { id, name -> viewModel.renameProfile(id, name) },
                onDeleteProfile = { viewModel.deleteProfile(it) },
                onUpdateSlot = { slotId, action, label ->
                    viewModel.updateSlot(slotId, action, label)
                },
            )
        }
    }
}
