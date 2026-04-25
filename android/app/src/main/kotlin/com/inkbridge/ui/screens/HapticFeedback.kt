package com.inkbridge.ui.screens

/**
 * Testable abstraction over Android's haptic feedback API.
 *
 * The default production implementation calls
 * [android.view.View.performHapticFeedback] with
 * [android.view.HapticFeedbackConstants.CONFIRM] (API 30+) or
 * [android.view.HapticFeedbackConstants.KEYBOARD_TAP] (API 26 minSdk fallback).
 *
 * Injecting this interface into [ConnectionViewModel] keeps haptic calls
 * out of the unit-test tier (no Android View required).
 */
fun interface HapticFeedback {
    /** Trigger a short confirmation-style haptic pulse. */
    fun performTapFeedback()
}
