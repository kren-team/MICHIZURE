package com.kren.michizure.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.kren.michizure.enforcement.AndroidPackageCatalog
import com.kren.michizure.enforcement.PackageCatalog
import com.kren.michizure.persistence.SelectedPackageStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class DeviceControlMethodHandler(
    private val context: Context,
    private val capabilitiesProvider: DeviceCapabilitiesProvider =
        DeviceCapabilitiesProvider(context),
    private val packageCatalog: PackageCatalog = AndroidPackageCatalog(context),
    private val selectedPackageStore: SelectedPackageStore =
        SelectedPackageStore(context),
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!DeviceControlContract.hasSupportedVersion(call.arguments)) {
            result.error(
                DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
                "The app and Android bridge versions do not match.",
                DeviceControlContract.versionedPayload(),
            )
            return
        }

        when (call.method) {
            DeviceControlContract.METHOD_GET_CAPABILITIES -> runSafely(result) {
                capabilitiesProvider.getCapabilities()
            }
            DeviceControlContract.METHOD_OPEN_USAGE_ACCESS_SETTINGS -> {
                runSafely(result) {
                    openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    DeviceControlContract.versionedPayload()
                }
            }
            DeviceControlContract.METHOD_OPEN_NOTIFICATION_SETTINGS -> {
                runSafely(result) {
                    openSettings(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                            .setData(Uri.parse("package:${context.packageName}")),
                    )
                    DeviceControlContract.versionedPayload()
                }
            }
            DeviceControlContract.METHOD_LIST_LOCKABLE_APPS -> {
                runSafely(result) {
                    val apps =
                        packageCatalog.listLockableApps().map { app ->
                            mapOf(
                                "packageName" to app.packageName,
                                "label" to app.label,
                                "isSelectable" to app.isSelectable,
                                "protectionReason" to app.protectionReason?.wireValue,
                            )
                        }
                    DeviceControlContract.versionedPayload(mapOf("apps" to apps))
                }
            }
            DeviceControlContract.METHOD_GET_SELECTED_PACKAGES -> {
                scope.launch {
                    runCatching { selectedPackageStore.read() }
                        .onSuccess { packages ->
                            postSuccess(
                                result,
                                DeviceControlContract.versionedPayload(
                                    mapOf("packageNames" to packages.sorted()),
                                ),
                            )
                        }
                        .onFailure { postNativeStateError(result) }
                }
            }
            DeviceControlContract.METHOD_SAVE_SELECTED_PACKAGES -> {
                val packageNames = parsePackageNames(call.arguments)
                if (packageNames == null) {
                    result.error(
                        DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
                        "The selected package payload is invalid.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                val catalogByPackage =
                    runCatching {
                        packageCatalog.listLockableApps().associateBy { it.packageName }
                    }.getOrElse {
                        postNativeUnavailable(result)
                        return
                    }
                val unavailable =
                    packageNames.firstOrNull { catalogByPackage[it] == null }
                if (unavailable != null) {
                    result.error(
                        DeviceControlContract.ERROR_PACKAGE_NOT_INSTALLED,
                        "A selected app is no longer available.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                val protectedPackage =
                    packageNames.firstOrNull {
                        catalogByPackage.getValue(it).isSelectable.not()
                    }
                if (protectedPackage != null) {
                    result.error(
                        DeviceControlContract.ERROR_PACKAGE_PROTECTED,
                        "A protected system app cannot be selected.",
                        DeviceControlContract.versionedPayload(),
                    )
                    return
                }
                scope.launch {
                    runCatching { selectedPackageStore.save(packageNames) }
                        .onSuccess {
                            postSuccess(
                                result,
                                DeviceControlContract.versionedPayload(
                                    mapOf("packageNames" to packageNames.sorted()),
                                ),
                            )
                        }
                        .onFailure { postNativeStateError(result) }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun close() {
        scope.cancel()
    }

    private fun openSettings(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun runSafely(
        result: MethodChannel.Result,
        action: () -> Map<String, Any?>,
    ) {
        runCatching(action)
            .onSuccess(result::success)
            .onFailure { postNativeUnavailable(result) }
    }

    private fun parsePackageNames(arguments: Any?): Set<String>? {
        val payload = arguments as? Map<*, *> ?: return null
        val values = payload["packageNames"] as? List<*> ?: return null
        if (values.any { it !is String || it.isBlank() }) {
            return null
        }
        return values.filterIsInstance<String>().toSet()
    }

    private fun postSuccess(
        result: MethodChannel.Result,
        payload: Map<String, Any?>,
    ) {
        mainHandler.post { result.success(payload) }
    }

    private fun postNativeStateError(result: MethodChannel.Result) {
        mainHandler.post {
            result.error(
                DeviceControlContract.ERROR_NATIVE_STATE_CORRUPT,
                "The local app selection could not be read or saved.",
                DeviceControlContract.versionedPayload(),
            )
        }
    }

    private fun postNativeUnavailable(result: MethodChannel.Result) {
        result.error(
            DeviceControlContract.ERROR_NATIVE_UNAVAILABLE,
            "The requested Android operation is unavailable.",
            DeviceControlContract.versionedPayload(),
        )
    }
}
