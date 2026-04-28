package com.inkbridge.app

import android.app.Application
import android.content.Context
import android.net.wifi.WifiManager
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.inkbridge.data.connection.ConnectionManager
import com.inkbridge.data.discovery.BroadcastDiscoveryRepository
import com.inkbridge.data.discovery.RealMulticastLockHolder
import com.inkbridge.data.settings.SettingsRepository
import com.inkbridge.ui.screens.ConnectionViewModel

/**
 * Manual DI factory for [ConnectionViewModel].
 *
 * Constructs the real discovery chain:
 *   [RealMulticastLockHolder] ← system [WifiManager]
 *   [BroadcastDiscoveryRepository] ← lock holder
 *   [ConnectionViewModel] ← repository injected as [HostDiscoverer]
 *
 * Injected in [MainActivity] so the ViewModel has a live [HostDiscoverer]
 * from first creation.
 */
class ConnectionViewModelFactory(
    private val application: Application,
) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        require(modelClass == ConnectionViewModel::class.java) {
            "ConnectionViewModelFactory only creates ConnectionViewModel"
        }

        val wifiManager = application.getSystemService(Context.WIFI_SERVICE) as WifiManager

        val lockHolder = RealMulticastLockHolder(wifiManager)
        val discoverer = BroadcastDiscoveryRepository(lockHolder)

        return ConnectionViewModel(
            application = application,
            connectionManager = ConnectionManager(),
            settings = SettingsRepository(
                application.getSharedPreferences("inkbridge_settings", Context.MODE_PRIVATE),
            ),
            hostDiscoverer = discoverer,
        ) as T
    }
}
