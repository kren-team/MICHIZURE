package com.kren.michizure.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DeviceControlMethodHandler(
    private val context: Context,
    private val capabilitiesProvider: DeviceCapabilitiesProvider =
        DeviceCapabilitiesProvider(context),
) : MethodChannel.MethodCallHandler {
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
            DeviceControlContract.METHOD_GET_CAPABILITIES ->
                result.success(capabilitiesProvider.getCapabilities())
            DeviceControlContract.METHOD_OPEN_USAGE_ACCESS_SETTINGS -> {
                openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(DeviceControlContract.versionedPayload())
            }
            DeviceControlContract.METHOD_OPEN_NOTIFICATION_SETTINGS -> {
                openSettings(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        .setData(Uri.parse("package:${context.packageName}")),
                )
                result.success(DeviceControlContract.versionedPayload())
            }
            else -> result.notImplemented()
        }
    }

    private fun openSettings(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
