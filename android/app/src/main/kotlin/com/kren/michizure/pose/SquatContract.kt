package com.kren.michizure.pose

object SquatContract {
    const val METHOD_CHANNEL = "com.kren.michizure/squat_control/v1"
    const val EVENT_CHANNEL = "com.kren.michizure/squat_events/v1"
    const val PREVIEW_VIEW_TYPE = "com.kren.michizure/pose_preview/v1"
    const val CONTRACT_VERSION = 1

    const val METHOD_GET_CAMERA_PERMISSION = "getCameraPermissionState"
    const val METHOD_REQUEST_CAMERA_PERMISSION = "requestCameraPermission"
    const val METHOD_OPEN_APP_SETTINGS = "openAppSettings"
    const val METHOD_START_SESSION = "startSession"
    const val METHOD_STOP_SESSION = "stopSession"
    const val METHOD_GET_SESSION_STATE = "getSessionState"
    const val METHOD_RUN_DEBUG_POSE_FIXTURE = "runDebugPoseFixture"
    const val METHOD_SET_DEBUG_THUMBNAIL = "setDebugPoseThumbnailEnabled"

    const val ERROR_CONTRACT_MISMATCH = "channelContractMismatch"
    const val ERROR_CAMERA_PERMISSION_DENIED = "cameraPermissionDenied"
    const val ERROR_CAMERA_PERMISSION_PERMANENTLY_DENIED =
        "cameraPermissionPermanentlyDenied"
    const val ERROR_CAMERA_UNAVAILABLE = "cameraUnavailable"
    const val ERROR_SESSION_CONFLICT = "sessionConflict"
    const val ERROR_NATIVE_UNAVAILABLE = "nativeUnavailable"

    fun versioned(values: Map<String, Any?> = emptyMap()): Map<String, Any?> =
        mapOf("contractVersion" to CONTRACT_VERSION) + values

    fun supports(arguments: Any?): Boolean =
        (arguments as? Map<*, *>)?.get("contractVersion") == CONTRACT_VERSION
}
