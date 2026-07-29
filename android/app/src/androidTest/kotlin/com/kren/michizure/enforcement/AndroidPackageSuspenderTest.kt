package com.kren.michizure.enforcement

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidPackageSuspenderTest {
    @Test
    fun deviceOwnerAppliesTargetAndReportsProtectedSelfAsPartialFailure() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val suspender = AndroidPackageSuspender(context)
        val target =
            AndroidPackageCatalog(context)
                .listLockableApps()
                .firstOrNull { it.isSelectable }

        if (!suspender.isDeviceOwner()) {
            val result = suspender.setSuspended(setOf(context.packageName), true)
            assertEquals(LockErrorCode.NOT_DEVICE_OWNER, result.capabilityError)
            assertEquals(setOf(context.packageName), result.failedPackages)
            return
        }

        requireNotNull(target) { "Managed emulator needs one selectable launcher app" }
        try {
            val result =
                suspender.setSuspended(
                    setOf(target.packageName, context.packageName),
                    true,
                )
            assertTrue(target.packageName in result.changedPackages)
            assertTrue(context.packageName in result.failedPackages)
            assertTrue(
                target.packageName in
                    suspender.querySuspended(setOf(target.packageName)).changedPackages,
            )
        } finally {
            val release = suspender.setSuspended(setOf(target.packageName), false)
            assertFalse(target.packageName in release.failedPackages)
        }
    }
}
