package com.kren.michizure.platform

import android.app.admin.DevicePolicyManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DeviceCapabilitiesProviderTest {
    @Test
    fun reportsTheActualDeviceOwnerStateWithoutThrowing() {
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val expected =
            context.getSystemService(DevicePolicyManager::class.java)
                .isDeviceOwnerApp(context.packageName)

        val capabilities = DeviceCapabilitiesProvider(context).getCapabilities()

        assertEquals(1, capabilities["contractVersion"])
        assertEquals(expected, capabilities["isDeviceOwner"])
        assertNotNull(capabilities["hasUsageAccess"])
        assertNotNull(capabilities["hasNotificationPermission"])
        assertNotNull(capabilities["hasBroadPackageVisibility"])
    }
}
