package com.inkbridge.ui.theme

import androidx.compose.ui.graphics.Color

// ── InkBridge Dark OLED palette ──────────────────────────────────────────────
// Design system: pro drawing tool for stylus input. Always dark, high contrast,
// minimal chrome, accent colours reserved for state and interaction.

// Base surface hierarchy — pure OLED-friendly blacks.
val InkBlack = Color(0xFF0A0A0A)          // root background
val InkSurface = Color(0xFF121212)        // cards, sheets
val InkSurfaceVariant = Color(0xFF1A1A1A) // raised surfaces (tab rows)
val InkSurfaceContainer = Color(0xFF1E1E1E)      // inputs, chips
val InkSurfaceContainerHigh = Color(0xFF262626)  // elevated modals
val InkOutline = Color(0xFF2E2E2E)        // hairlines, borders
val InkOutlineVariant = Color(0xFF1F1F1F) // quieter dividers

// Foreground tiers (on surfaces above).
val InkOnSurface = Color(0xFFF5F5F5)           // primary text
val InkOnSurfaceVariant = Color(0xFF9CA3AF)    // secondary text (gray-400 eq.)
val InkOnSurfaceMuted = Color(0xFF6B7280)      // hints, helper text (gray-500)

// Primary — electric blue. Used for CTAs, links, selected state.
val InkPrimary = Color(0xFF3B82F6)        // blue-500
val InkOnPrimary = Color(0xFFFFFFFF)
val InkPrimaryContainer = Color(0xFF1E3A8A)  // blue-900, low-emphasis fills
val InkOnPrimaryContainer = Color(0xFFBFDBFE) // blue-200

// Secondary — cyan/teal. Used for connected state + canvas feedback.
val InkSecondary = Color(0xFF22D3EE)      // cyan-400
val InkOnSecondary = Color(0xFF083344)    // cyan-950
val InkSecondaryContainer = Color(0xFF155E75) // cyan-800
val InkOnSecondaryContainer = Color(0xFFA5F3FC) // cyan-200

// Tertiary — amber. Warnings, pending, degraded states.
val InkTertiary = Color(0xFFFBBF24)       // amber-400
val InkOnTertiary = Color(0xFF451A03)     // amber-950
val InkTertiaryContainer = Color(0xFF78350F) // amber-900
val InkOnTertiaryContainer = Color(0xFFFDE68A) // amber-200

// Error — soft red (not aggressive).
val InkError = Color(0xFFF87171)          // red-400
val InkOnError = Color(0xFF450A0A)        // red-950
val InkErrorContainer = Color(0xFF7F1D1D) // red-900
val InkOnErrorContainer = Color(0xFFFECACA) // red-200

// Canvas-specific — colours used on the CaptureSurface dot grid.
val CanvasBackground = InkBlack            // same as root, edge-to-edge feel
val CanvasDot = Color(0xFF262626)          // subtle, ~15% relative lightness
val CanvasDotActive = Color(0xFF3F3F3F)    // slightly brighter when connected
val CanvasFeedbackGlow = InkSecondary      // cyan — stylus feedback
