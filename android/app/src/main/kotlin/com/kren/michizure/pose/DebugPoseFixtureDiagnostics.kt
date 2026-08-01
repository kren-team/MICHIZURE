package com.kren.michizure.pose

import android.content.Context

data class PoseFixtureDiagnosticResult(
    val callbackDelivered: Boolean,
    val poseCount: Int,
    val hipAvailable: Boolean,
    val kneeAvailable: Boolean,
    val ankleAvailable: Boolean,
    val errorCode: String?,
)

interface DebugPoseFixtureDiagnostics : AutoCloseable {
    fun run(callback: (PoseFixtureDiagnosticResult) -> Unit)
}

object DebugPoseFixtureDiagnosticsFactory {
    fun create(context: Context): DebugPoseFixtureDiagnostics? =
        runCatching {
            Class
                .forName(DEBUG_IMPLEMENTATION)
                .getConstructor(Context::class.java)
                .newInstance(context) as DebugPoseFixtureDiagnostics
        }.getOrNull()

    private const val DEBUG_IMPLEMENTATION =
        "com.kren.michizure.pose.GeneratedPoseFixtureDiagnostics"
}
