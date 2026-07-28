package com.kren.michizure.platform

object DeviceControlContract {
    const val CHANNEL_NAME = "com.kren.michizure/device_control/v1"
    const val CONTRACT_VERSION = 1

    const val METHOD_GET_CAPABILITIES = "getCapabilities"
    const val METHOD_OPEN_USAGE_ACCESS_SETTINGS = "openUsageAccessSettings"
    const val METHOD_OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
    const val METHOD_LIST_LOCKABLE_APPS = "listLockableApps"
    const val METHOD_GET_SELECTED_PACKAGES = "getSelectedPackages"
    const val METHOD_SAVE_SELECTED_PACKAGES = "saveSelectedPackages"

    const val ERROR_CHANNEL_CONTRACT_MISMATCH = "channelContractMismatch"
    const val ERROR_PACKAGE_PROTECTED = "packageProtected"
    const val ERROR_PACKAGE_NOT_INSTALLED = "packageNotInstalled"
    const val ERROR_NATIVE_STATE_CORRUPT = "nativeStateCorrupt"
    const val ERROR_NATIVE_UNAVAILABLE = "nativeUnavailable"

    fun hasSupportedVersion(arguments: Any?): Boolean {
        val payload = arguments as? Map<*, *> ?: return false
        return payload["contractVersion"] == CONTRACT_VERSION
    }

    fun versionedPayload(values: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        return mapOf("contractVersion" to CONTRACT_VERSION) + values
    }
}
