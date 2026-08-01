package com.kren.michizure.monitoring

class ForegroundTransitionClassifier(
    private val window: TaskGuardWindow,
    private val systemFlowLeases: SystemFlowLeaseRegistry =
        SystemFlowLeaseRegistry(),
    private val dwellMs: Long = DEFAULT_DWELL_MS,
) {
    private data class Candidate(
        val packageName: String,
        val originElapsedMs: Long,
    )

    private data class EventSignature(
        val packageName: String,
        val className: String,
        val wallTimeMs: Long,
    )

    private var candidate: Candidate? = null
    private var terminal: TaskGuardTerminal? = null
    private val recentSignatures = LinkedHashSet<EventSignature>()

    init {
        require(window.taskSessionId.isNotBlank())
        require(window.ownPackageName.isNotBlank())
        require(window.expectedEndElapsedMs >= window.startedElapsedMs)
        require(dwellMs >= 0)
    }

    fun onForegroundResume(
        event: ForegroundResumeEvent,
        interruption: InterruptionSnapshot = InterruptionSnapshot(),
    ): TaskGuardTerminal? {
        terminal?.let { return it }
        if (event.eventElapsedMs < window.startedElapsedMs ||
            !remember(event)
        ) {
            return null
        }
        if (event.packageName == window.ownPackageName) {
            candidate = null
            return evaluate(event.eventElapsedMs, interruption)
        }
        if (isInterrupted(event.packageName, event.eventElapsedMs, interruption)) {
            candidate = null
            return null
        }
        if (event.eventElapsedMs >= window.expectedEndElapsedMs &&
            candidate == null
        ) {
            return commitDeadline(event.eventElapsedMs)
        }
        if (event.eventElapsedMs >= window.expectedEndElapsedMs) {
            return evaluate(event.eventElapsedMs, interruption)
        }

        val existing = candidate
        if (existing == null || existing.packageName != event.packageName) {
            candidate =
                Candidate(
                    packageName = event.packageName,
                    originElapsedMs = event.eventElapsedMs,
                )
        }
        return evaluate(event.eventElapsedMs, interruption)
    }

    fun evaluate(
        nowElapsedMs: Long,
        interruption: InterruptionSnapshot = InterruptionSnapshot(),
    ): TaskGuardTerminal? {
        terminal?.let { return it }
        val current = candidate
        if (current != null) {
            if (isInterrupted(current.packageName, nowElapsedMs, interruption)) {
                candidate = null
                return null
            }
            if (nowElapsedMs - current.originElapsedMs >= dwellMs) {
                return commitFailure(
                    TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
                    current.originElapsedMs,
                )
            }
            // A pre-deadline candidate owns the boundary until its dwell resolves.
            return null
        }
        if (nowElapsedMs >= window.expectedEndElapsedMs) {
            return commitDeadline(window.expectedEndElapsedMs)
        }
        return null
    }

    fun onCapabilityLost(nowElapsedMs: Long): TaskGuardTerminal {
        return terminal ?: commitFailure(
            TaskGuardFailureReason.MONITOR_CAPABILITY_LOST,
            nowElapsedMs,
        )
    }

    fun onBootDiscontinuity(nowElapsedMs: Long): TaskGuardTerminal {
        return terminal ?: commitFailure(
            TaskGuardFailureReason.RECOVERY_DETECTED_VIOLATION,
            nowElapsedMs,
        )
    }

    private fun isInterrupted(
        packageName: String,
        nowElapsedMs: Long,
        interruption: InterruptionSnapshot,
    ): Boolean {
        if (!interruption.isInteractive || interruption.isKeyguardLocked) {
            return true
        }
        if (interruption.isCallActive &&
            packageName == interruption.defaultDialerPackage
        ) {
            return true
        }
        return systemFlowLeases.consumes(packageName, nowElapsedMs)
    }

    private fun remember(event: ForegroundResumeEvent): Boolean {
        val signature =
            EventSignature(
                packageName = event.packageName,
                className = event.className,
                wallTimeMs = event.eventWallTimeMs,
            )
        if (!recentSignatures.add(signature)) {
            return false
        }
        while (recentSignatures.size > MAX_RECENT_EVENTS) {
            recentSignatures.remove(recentSignatures.first())
        }
        return true
    }

    private fun commitFailure(
        reason: TaskGuardFailureReason,
        originElapsedMs: Long,
    ): TaskGuardTerminal {
        return TaskGuardTerminal(
            kind = TaskGuardTerminalKind.TASK_FAILED,
            failureReason = reason,
            originElapsedMs = originElapsedMs,
        ).also {
            candidate = null
            terminal = it
        }
    }

    private fun commitDeadline(originElapsedMs: Long): TaskGuardTerminal {
        return TaskGuardTerminal(
            kind = TaskGuardTerminalKind.DEADLINE_REACHED,
            failureReason = null,
            originElapsedMs = originElapsedMs,
        ).also {
            candidate = null
            terminal = it
        }
    }

    companion object {
        const val DEFAULT_DWELL_MS = 600L
        private const val MAX_RECENT_EVENTS = 256
    }
}
