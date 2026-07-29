package com.kren.michizure.monitoring

enum class TaskGuardTerminalKind {
    TASK_FAILED,
    DEADLINE_REACHED,
}

enum class TaskGuardFailureReason(val wireValue: String) {
    FOREIGN_APP_FOREGROUND("foreign_app_foreground"),
    MONITOR_CAPABILITY_LOST("monitor_capability_lost"),
    RECOVERY_DETECTED_VIOLATION("recovery_detected_violation"),
}

data class TaskGuardTerminal(
    val kind: TaskGuardTerminalKind,
    val failureReason: TaskGuardFailureReason?,
    val originElapsedMs: Long,
)

data class TaskGuardWindow(
    val taskSessionId: String,
    val ownPackageName: String,
    val startedElapsedMs: Long,
    val expectedEndElapsedMs: Long,
)

data class ForegroundResumeEvent(
    val packageName: String,
    val className: String,
    val eventWallTimeMs: Long,
    val eventElapsedMs: Long,
)

data class InterruptionSnapshot(
    val isInteractive: Boolean = true,
    val isKeyguardLocked: Boolean = false,
    val isCallActive: Boolean = false,
    val defaultDialerPackage: String? = null,
)
