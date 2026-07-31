package com.kren.michizure.pose

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.kren.michizure.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SquatMethodHandler(
    private val activity: MainActivity,
    private val manager: SquatSessionManager,
) : MethodChannel.MethodCallHandler {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val permissionPreferences =
        activity.getSharedPreferences(PERMISSION_PREFERENCES, 0)
    private val debugFixtureDiagnostics by lazy {
        if (isDebuggable) {
            DebugPoseFixtureDiagnosticsFactory.create(activity.applicationContext)
        } else {
            null
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!SquatContract.supports(call.arguments)) {
            result.error(
                SquatContract.ERROR_CONTRACT_MISMATCH,
                "The squat channel contract version is unsupported.",
                SquatContract.versioned(),
            )
            return
        }
        when (call.method) {
            SquatContract.METHOD_GET_CAMERA_PERMISSION ->
                result.success(permissionPayload(call.arguments))
            SquatContract.METHOD_REQUEST_CAMERA_PERMISSION ->
                requestPermission(call.arguments, result)
            SquatContract.METHOD_OPEN_APP_SETTINGS -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                result.success(SquatContract.versioned())
            }
            SquatContract.METHOD_START_SESSION -> startSession(call.arguments, result)
            SquatContract.METHOD_STOP_SESSION -> {
                val payload = call.arguments as? Map<*, *>
                val id = stringArgument(call.arguments, "squatSessionId")
                if (payload?.containsKey("squatSessionId") == true && id == null) {
                    result.error(
                        SquatContract.ERROR_CONTRACT_MISMATCH,
                        "The squat stop payload is invalid.",
                        SquatContract.versioned(),
                    )
                    return
                }
                result.success(
                    SquatContract.versioned(
                        mapOf(
                            "stopped" to manager.stop(id),
                            "squatSessionId" to id,
                        ),
                    ),
                )
            }
            SquatContract.METHOD_GET_SESSION_STATE ->
                result.success(manager.statePayload())
            SquatContract.METHOD_RUN_DEBUG_POSE_FIXTURE ->
                runDebugPoseFixture(result)
            SquatContract.METHOD_SET_DEBUG_THUMBNAIL ->
                setDebugThumbnail(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        permissionPreferences.edit().putBoolean(HAS_REQUESTED_CAMERA, true).apply()
        val result = pendingPermissionResult
        pendingPermissionResult = null
        result?.success(permissionPayload(null))
        return true
    }

    fun close() {
        pendingPermissionResult?.error(
            SquatContract.ERROR_NATIVE_UNAVAILABLE,
            "The camera permission request was interrupted.",
            SquatContract.versioned(),
        )
        pendingPermissionResult = null
        debugFixtureDiagnostics?.close()
    }

    private fun runDebugPoseFixture(result: MethodChannel.Result) {
        val diagnostics = debugFixtureDiagnostics
        if (!isDebuggable || diagnostics == null) {
            result.notImplemented()
            return
        }
        diagnostics.run { fixture ->
            activity.runOnUiThread {
                result.success(
                    SquatContract.versioned(
                        mapOf(
                            "callbackDelivered" to fixture.callbackDelivered,
                            "poseCount" to fixture.poseCount,
                            "hipAvailable" to fixture.hipAvailable,
                            "kneeAvailable" to fixture.kneeAvailable,
                            "ankleAvailable" to fixture.ankleAvailable,
                            "errorCode" to fixture.errorCode,
                        ),
                    ),
                )
            }
        }
    }

    private fun setDebugThumbnail(
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        if (!isDebuggable) {
            result.notImplemented()
            return
        }
        val enabled = (arguments as? Map<*, *>)?.get("enabled") as? Boolean
        if (enabled == null) {
            result.error(
                SquatContract.ERROR_CONTRACT_MISMATCH,
                "The debug thumbnail payload is invalid.",
                SquatContract.versioned(),
            )
            return
        }
        manager.setDebugThumbnailEnabled(enabled)
        result.success(SquatContract.versioned(mapOf("enabled" to enabled)))
    }

    private fun requestPermission(arguments: Any?, result: MethodChannel.Result) {
        if (!PoseSourceMode.fromCreationParams(arguments).requiresCameraPermission) {
            result.success(permissionPayload(arguments))
            return
        }
        if (hasCameraPermission()) {
            result.success(permissionPayload(arguments))
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                SquatContract.ERROR_NATIVE_UNAVAILABLE,
                "A camera permission request is already active.",
                SquatContract.versioned(),
            )
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            CAMERA_PERMISSION_REQUEST,
        )
    }

    private fun startSession(
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val mode = PoseSourceMode.fromCreationParams(arguments)
        if (mode.requiresCameraPermission && !hasCameraPermission()) {
            val state = permissionState()
            val code =
                if (state == "permanentlyDenied") {
                    SquatContract.ERROR_CAMERA_PERMISSION_PERMANENTLY_DENIED
                } else {
                    SquatContract.ERROR_CAMERA_PERMISSION_DENIED
                }
            result.error(code, "Camera permission is required.", permissionPayload(arguments))
            return
        }
        val sessionId = stringArgument(arguments, "squatSessionId")
        val debtId = stringArgument(arguments, "debtId")
        if (sessionId == null || debtId == null || !SESSION_ID.matches(sessionId)) {
            result.error(
                SquatContract.ERROR_CONTRACT_MISMATCH,
                "The squat session payload is invalid.",
                SquatContract.versioned(),
            )
            return
        }
        runCatching {
            manager.start(NativeSquatSession(sessionId, debtId))
        }.onSuccess { changed ->
            result.success(
                SquatContract.versioned(
                    mapOf(
                        "started" to true,
                        "changed" to changed,
                        "squatSessionId" to sessionId,
                        "detectorVersion" to SquatDetectorConfig.VERSION,
                    ),
                ),
            )
        }.onFailure {
            result.error(
                SquatContract.ERROR_SESSION_CONFLICT,
                "Another squat session is already active.",
                manager.statePayload(),
            )
        }
    }

    private fun permissionPayload(arguments: Any?): Map<String, Any?> =
        SquatContract.versioned(
            mapOf(
                "state" to
                    if (PoseSourceMode.fromCreationParams(arguments).requiresCameraPermission) {
                        permissionState()
                    } else {
                        "granted"
                    },
            ),
        )

    private fun permissionState(): String {
        if (hasCameraPermission()) return "granted"
        val requested = permissionPreferences.getBoolean(HAS_REQUESTED_CAMERA, false)
        return if (requested &&
            !ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.CAMERA,
            )
        ) {
            "permanentlyDenied"
        } else {
            "denied"
        }
    }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED

    private val isDebuggable: Boolean
        get() =
            activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private fun stringArgument(
        arguments: Any?,
        key: String,
    ): String? =
        ((arguments as? Map<*, *>)?.get(key) as? String)
            ?.takeIf { it.isNotBlank() && !it.contains('/') }

    companion object {
        private const val CAMERA_PERMISSION_REQUEST = 9109
        private const val PERMISSION_PREFERENCES = "squat_permission_state_v1"
        private const val HAS_REQUESTED_CAMERA = "has_requested_camera"
        private val SESSION_ID = Regex("^[A-Za-z0-9-]{16,64}$")
    }
}
