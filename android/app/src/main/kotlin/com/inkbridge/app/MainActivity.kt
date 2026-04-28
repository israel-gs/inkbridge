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
 * Manual DI: [ConnectionViewModel] is instantiated via [ConnectionViewModelFactory],
 * which constructs the real broadcast-discovery chain so host discovery is
 * live from first launch.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            InkBridgeTheme {
                val viewModel: ConnectionViewModel = viewModel(
                    factory = ConnectionViewModelFactory(application),
                )
                InkBridgeApp(viewModel = viewModel)
            }
        }
    }
}
