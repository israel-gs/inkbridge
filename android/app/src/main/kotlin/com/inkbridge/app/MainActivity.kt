package com.inkbridge.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.inkbridge.app.ui.theme.InkBridgeTheme
import com.inkbridge.ui.screens.ConnectionViewModel
import com.inkbridge.ui.screens.InkBridgeApp

/**
 * Single-Activity entry point.
 *
 * Manual DI: [ConnectionViewModel] is instantiated via AndroidViewModel factory
 * (no Hilt in this change — keeps dependencies minimal for the foundation spike).
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            InkBridgeTheme {
                val viewModel: ConnectionViewModel = viewModel()
                InkBridgeApp(viewModel = viewModel)
            }
        }
    }
}
