package com.kren.michizure.enforcement

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager
import java.util.Locale

enum class PackageProtectionReason(val wireValue: String) {
    SELF("self"),
    DEVICE_ADMIN("deviceAdmin"),
    LAUNCHER("launcher"),
    DIALER("dialer"),
    PERMISSION_CONTROLLER("permissionController"),
    SETTINGS("settings"),
    PACKAGE_MANAGER("packageManager"),
}

data class PackageCandidate(
    val packageName: String,
    val label: String,
    val isLaunchable: Boolean,
    val protectionReason: PackageProtectionReason? = null,
)

data class CatalogApp(
    val packageName: String,
    val label: String,
    val isSelectable: Boolean,
    val protectionReason: PackageProtectionReason?,
)

class PackageCandidateFilter {
    fun filter(candidates: List<PackageCandidate>): List<CatalogApp> {
        return candidates
            .asSequence()
            .filter { it.isLaunchable }
            .distinctBy { it.packageName }
            .map {
                CatalogApp(
                    packageName = it.packageName,
                    label = it.label.ifBlank { it.packageName },
                    isSelectable = it.protectionReason == null,
                    protectionReason = it.protectionReason,
                )
            }
            .sortedWith(
                compareBy<CatalogApp>(
                    { it.label.lowercase(Locale.ROOT) },
                    { it.packageName },
                ),
            )
            .toList()
    }
}

interface PackageCatalog {
    fun listLockableApps(): List<CatalogApp>
}

data class LaunchableApp(
    val packageName: String,
    val label: String,
)

fun interface LaunchableAppDiscovery {
    fun discover(): List<LaunchableApp>
}

fun interface ProtectedPackageResolver {
    fun resolve(): Map<String, PackageProtectionReason>
}

class AndroidPackageCatalog(
    private val discovery: LaunchableAppDiscovery,
    private val protectedPackageResolver: ProtectedPackageResolver,
    private val filter: PackageCandidateFilter = PackageCandidateFilter(),
) : PackageCatalog {
    constructor(
        context: Context,
        filter: PackageCandidateFilter = PackageCandidateFilter(),
    ) : this(
        discovery = LauncherAppsDiscovery(context),
        protectedPackageResolver = AndroidProtectedPackageResolver(context),
        filter = filter,
    )

    override fun listLockableApps(): List<CatalogApp> {
        val protectedPackages = protectedPackageResolver.resolve()
        val candidates =
            discovery.discover().map { app ->
                PackageCandidate(
                    packageName = app.packageName,
                    label = app.label,
                    isLaunchable = true,
                    protectionReason = protectedPackages[app.packageName],
                )
            }
        return filter.filter(candidates)
    }
}

/**
 * Lists the activities the current Android user can launch from a Launcher.
 *
 * LauncherApps is the platform's launcher-facing catalog and does not require
 * QUERY_ALL_PACKAGES. Package removal can race this call, so stale activities
 * are skipped independently instead of failing the entire catalog.
 */
class LauncherAppsDiscovery(context: Context) : LaunchableAppDiscovery {
    private val launcherApps =
        requireNotNull(context.getSystemService(LauncherApps::class.java)) {
            "LauncherApps is unavailable."
        }

    override fun discover(): List<LaunchableApp> {
        val user = android.os.Process.myUserHandle()
        return launcherApps
            .getActivityList(null, user)
            .mapNotNull { activity ->
                runCatching {
                    if (!launcherApps.isActivityEnabled(activity.componentName, user)) {
                        return@runCatching null
                    }
                    LaunchableApp(
                        packageName = activity.componentName.packageName,
                        label = activity.label?.toString().orEmpty(),
                    )
                }.getOrNull()
            }
    }
}

class AndroidProtectedPackageResolver(
    private val context: Context,
) : ProtectedPackageResolver {
    private val packageManager: PackageManager
        get() = context.packageManager

    override fun resolve(): Map<String, PackageProtectionReason> {
        val protected = linkedMapOf<String, PackageProtectionReason>()
        protected[context.packageName] = PackageProtectionReason.SELF

        val devicePolicyManager =
            context.getSystemService(DevicePolicyManager::class.java)
        devicePolicyManager?.activeAdmins.orEmpty().forEach { admin ->
            protected.putIfAbsent(
                admin.packageName,
                PackageProtectionReason.DEVICE_ADMIN,
            )
        }

        resolveActivityPackage(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
        )?.let { protected.putIfAbsent(it, PackageProtectionReason.LAUNCHER) }

        context.getSystemService(TelecomManager::class.java)
            ?.defaultDialerPackage
            ?.let { protected.putIfAbsent(it, PackageProtectionReason.DIALER) }

        findPermissionControllerPackages().forEach {
            protected.putIfAbsent(
                it,
                PackageProtectionReason.PERMISSION_CONTROLLER,
            )
        }

        resolveActivityPackage(Intent(Settings.ACTION_SETTINGS))?.let {
            protected.putIfAbsent(it, PackageProtectionReason.SETTINGS)
        }

        findPackageManagerPackages().forEach {
            protected.putIfAbsent(
                it,
                PackageProtectionReason.PACKAGE_MANAGER,
            )
        }
        return protected
    }

    @Suppress("DEPRECATION")
    private fun findPackageManagerPackages(): Set<String> {
        val packages = linkedSetOf<String>()
        val packageUri = Uri.parse("package:${context.packageName}")
        val intents =
            listOf(
                Intent(Intent.ACTION_INSTALL_PACKAGE)
                    .setDataAndType(packageUri, PACKAGE_ARCHIVE_MIME_TYPE),
                Intent(Intent.ACTION_UNINSTALL_PACKAGE).setData(packageUri),
            )
        intents.forEach { intent ->
            queryIntentActivities(intent).forEach { resolveInfo ->
                resolveInfo.activityInfo?.packageName?.let(packages::add)
            }
        }
        val verificationIntent =
            Intent(Intent.ACTION_PACKAGE_NEEDS_VERIFICATION)
                .setDataAndType(packageUri, PACKAGE_ARCHIVE_MIME_TYPE)
        queryBroadcastReceivers(verificationIntent).forEach { resolveInfo ->
            resolveInfo.activityInfo?.packageName?.let(packages::add)
        }
        return packages
    }

    @Suppress("DEPRECATION")
    private fun findPermissionControllerPackages(): Set<String> {
        val packages =
            if (Build.VERSION.SDK_INT >= 33) {
                packageManager.getPackagesHoldingPermissions(
                    arrayOf(GRANT_RUNTIME_PERMISSIONS),
                    PackageManager.PackageInfoFlags.of(
                        PackageManager.MATCH_SYSTEM_ONLY.toLong(),
                    ),
                )
            } else {
                packageManager.getPackagesHoldingPermissions(
                    arrayOf(GRANT_RUNTIME_PERMISSIONS),
                    PackageManager.MATCH_SYSTEM_ONLY,
                )
            }
        return packages.mapTo(linkedSetOf()) { it.packageName }
    }

    private fun resolveActivityPackage(intent: Intent): String? {
        return resolveActivity(intent)?.activityInfo?.packageName
    }

    @Suppress("DEPRECATION")
    private fun resolveActivity(intent: Intent): ResolveInfo? {
        return if (Build.VERSION.SDK_INT >= 33) {
            packageManager.resolveActivity(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
    }

    @Suppress("DEPRECATION")
    private fun queryIntentActivities(intent: Intent): List<ResolveInfo> {
        return if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()),
            )
        } else {
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
        }
    }

    @Suppress("DEPRECATION")
    private fun queryBroadcastReceivers(intent: Intent): List<ResolveInfo> {
        return if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryBroadcastReceivers(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong()),
            )
        } else {
            packageManager.queryBroadcastReceivers(intent, PackageManager.MATCH_ALL)
        }
    }

    companion object {
        private const val PACKAGE_ARCHIVE_MIME_TYPE =
            "application/vnd.android.package-archive"
        private const val GRANT_RUNTIME_PERMISSIONS =
            "android.permission.GRANT_RUNTIME_PERMISSIONS"
    }
}
