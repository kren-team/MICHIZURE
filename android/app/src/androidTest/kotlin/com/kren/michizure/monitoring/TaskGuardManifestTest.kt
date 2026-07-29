package com.kren.michizure.monitoring

import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TaskGuardManifestTest {
    @Test
    fun taskGuardServiceIsPrivateAndDeclaresSystemExemptedType() {
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val serviceInfo =
            context.packageManager.getServiceInfo(
                ComponentName(context, TaskGuardService::class.java),
                PackageManager.ComponentInfoFlags.of(0),
            )

        assertFalse(serviceInfo.exported)
        if (Build.VERSION.SDK_INT >= 34) {
            assertEquals(
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
                serviceInfo.foregroundServiceType,
            )
        }
    }
}
