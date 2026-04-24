package com.inkbridge.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
            )
        }
    }
}
