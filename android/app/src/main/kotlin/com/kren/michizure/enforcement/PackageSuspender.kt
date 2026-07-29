package com.kren.michizure.enforcement

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.kren.michizure.admin.MichizureDeviceAdminReceiver

interface PackageSuspender {
    fun isDeviceOwner(): Boolean

    fun querySuspended(packageNames: Set<String>): PackageSuspensionResult

    fun setSuspended(
        packageNames: Set<String>,
        suspended: Boolean,
    ): PackageSuspensionResult
}

class AndroidPackageSuspender(
    private val context: Context,
) : PackageSuspender {
    private val devicePolicyManager =
        context.getSystemService(DevicePolicyManager::class.java)
    private val admin =
        ComponentName(context, MichizureDeviceAdminReceiver::class.java)

    override fun isDeviceOwner(): Boolean {
        return devicePolicyManager?.isDeviceOwnerApp(context.packageName) == true
    }

    override fun querySuspended(packageNames: Set<String>): PackageSuspensionResult {
        if (Build.VERSION.SDK_INT < 29) {
            return PackageSuspensionResult(
                requestedPackages = packageNames,
                changedPackages = emptySet(),
                failedPackages = packageNames,
                capabilityError = LockErrorCode.NOT_DEVICE_OWNER,
            )
        }
        val suspended = linkedSetOf<String>()
        val unavailable = linkedSetOf<String>()
        packageNames.forEach { packageName ->
            try {
                if (context.packageManager.isPackageSuspended(packageName)) {
                    suspended += packageName
                }
            } catch (_: PackageManager.NameNotFoundException) {
                unavailable += packageName
            } catch (_: SecurityException) {
                unavailable += packageName
            }
        }
        return PackageSuspensionResult(
            requestedPackages = packageNames,
            changedPackages = suspended,
            failedPackages = emptySet(),
            unavailablePackages = unavailable,
        )
    }

    override fun setSuspended(
        packageNames: Set<String>,
        suspended: Boolean,
    ): PackageSuspensionResult {
        if (packageNames.isEmpty()) {
            return PackageSuspensionResult(
                requestedPackages = emptySet(),
                changedPackages = emptySet(),
                failedPackages = emptySet(),
            )
        }
        if (!isDeviceOwner() || Build.VERSION.SDK_INT < 24) {
            return PackageSuspensionResult(
                requestedPackages = packageNames,
                changedPackages = emptySet(),
                failedPackages = packageNames,
                capabilityError = LockErrorCode.NOT_DEVICE_OWNER,
            )
        }
        return try {
            val failed =
                devicePolicyManager
                    ?.setPackagesSuspended(
                        admin,
                        packageNames.sorted().toTypedArray(),
                        suspended,
                    )
                    ?.toSet()
                    .orEmpty()
            PackageSuspensionResult(
                requestedPackages = packageNames,
                changedPackages = packageNames - failed,
                failedPackages = failed,
            )
        } catch (_: SecurityException) {
            PackageSuspensionResult(
                requestedPackages = packageNames,
                changedPackages = emptySet(),
                failedPackages = packageNames,
                capabilityError = LockErrorCode.NOT_DEVICE_OWNER,
            )
        } catch (_: IllegalArgumentException) {
            PackageSuspensionResult(
                requestedPackages = packageNames,
                changedPackages = emptySet(),
                failedPackages = packageNames,
            )
        }
    }
}
