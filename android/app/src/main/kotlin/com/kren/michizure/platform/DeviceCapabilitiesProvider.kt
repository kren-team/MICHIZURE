package com.kren.michizure.platform

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.os.UserManager

class DeviceCapabilitiesProvider(private val context: Context) {
    fun getCapabilities(): Map<String, Any?> {
        val devicePolicyManager =
            context.getSystemService(DevicePolicyManager::class.java)
        val userManager = context.getSystemService(UserManager::class.java)
        val notificationManager =
            context.getSystemService(NotificationManager::class.java)
        val isDeviceOwner =
            devicePolicyManager?.isDeviceOwnerApp(context.packageName) == true

        return DeviceControlContract.versionedPayload(
            mapOf(
                "isDeviceOwner" to isDeviceOwner,
                "hasUsageAccess" to hasUsageAccess(),
                "hasNotificationPermission" to
                    hasNotificationPermission(notificationManager),
                "hasBroadPackageVisibility" to hasBroadPackageVisibility(),
                "isUserUnlocked" to (userManager?.isUserUnlocked != false),
                "supportsHardEnforcement" to (Build.VERSION.SDK_INT >= 29),
                "sdkInt" to Build.VERSION.SDK_INT,
            ),
        )
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java)
            ?: return false
        val mode =
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasNotificationPermission(
        notificationManager: NotificationManager?,
    ): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return notificationManager?.areNotificationsEnabled() != false
    }

    private fun hasBroadPackageVisibility(): Boolean {
        return context.packageManager.checkPermission(
            Manifest.permission.QUERY_ALL_PACKAGES,
            context.packageName,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
