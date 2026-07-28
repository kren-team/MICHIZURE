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
    const val METHOD_START_TASK_GUARD = "startTaskGuard"
    const val METHOD_STOP_TASK_GUARD = "stopTaskGuard"
    const val METHOD_GET_TASK_GUARD_STATE = "getTaskGuardState"
    const val METHOD_ACK_TASK_EVENT = "ackTaskEvent"

    const val ERROR_CHANNEL_CONTRACT_MISMATCH = "channelContractMismatch"
    const val ERROR_PACKAGE_PROTECTED = "packageProtected"
    const val ERROR_PACKAGE_NOT_INSTALLED = "packageNotInstalled"
    const val ERROR_NATIVE_STATE_CORRUPT = "nativeStateCorrupt"
    const val ERROR_NATIVE_UNAVAILABLE = "nativeUnavailable"
    const val ERROR_NOT_DEVICE_OWNER = "notDeviceOwner"
    const val ERROR_USAGE_ACCESS_MISSING = "usageAccessMissing"
    const val ERROR_NOTIFICATION_PERMISSION_MISSING =
        "notificationPermissionMissing"
    const val ERROR_FOREGROUND_SERVICE_START_DENIED =
        "foregroundServiceStartDenied"

    fun hasSupportedVersion(arguments: Any?): Boolean {
        val payload = arguments as? Map<*, *> ?: return false
        return payload["contractVersion"] == CONTRACT_VERSION
    }

    fun versionedPayload(values: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        return mapOf("contractVersion" to CONTRACT_VERSION) + values
    }
}
