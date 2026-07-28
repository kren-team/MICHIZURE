package com.kren.michizure.monitoring

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ForegroundTransitionClassifierTest {
    private val window =
        TaskGuardWindow(
            taskSessionId = "task-1",
            ownPackageName = "com.kren.michizure",
            startedElapsedMs = 1_000,
            expectedEndElapsedMs = 10_000,
        )

    @Test
    fun ownAppContinuationDoesNotFail() {
        val classifier = ForegroundTransitionClassifier(window)

        assertNull(classifier.onForegroundResume(event("com.kren.michizure", 2_000)))
        assertNull(classifier.evaluate(3_000))
    }

    @Test
    fun foreignAppFailsOnlyAfterDwell() {
        val classifier = ForegroundTransitionClassifier(window)

        assertNull(classifier.onForegroundResume(event("com.android.chrome", 2_000)))
        assertNull(classifier.evaluate(2_599))
        assertFailure(
            classifier.evaluate(2_600),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            2_000,
        )
    }

    @Test
    fun ownAppReturnBeforeDwellCancelsCandidate() {
        val classifier = ForegroundTransitionClassifier(window)

        assertNull(classifier.onForegroundResume(event("com.android.chrome", 2_000)))
        assertNull(classifier.onForegroundResume(event("com.kren.michizure", 2_500)))
        assertNull(classifier.evaluate(3_000))
    }

    @Test
    fun screenOffAndKeyguardCancelCandidates() {
        val screenOffClassifier = ForegroundTransitionClassifier(window)
        screenOffClassifier.onForegroundResume(event("com.android.chrome", 2_000))
        assertNull(
            screenOffClassifier.evaluate(
                2_600,
                InterruptionSnapshot(isInteractive = false),
            ),
        )
        assertNull(screenOffClassifier.evaluate(2_700))

        val keyguardClassifier = ForegroundTransitionClassifier(window)
        keyguardClassifier.onForegroundResume(event("com.android.chrome", 2_000))
        assertNull(
            keyguardClassifier.evaluate(
                2_600,
                InterruptionSnapshot(isKeyguardLocked = true),
            ),
        )
        assertNull(keyguardClassifier.evaluate(2_700))
    }

    @Test
    fun explicitSystemFlowRequiresAnUnexpiredMatchingLease() {
        val leases = SystemFlowLeaseRegistry()
        val classifier = ForegroundTransitionClassifier(window, leases)
        leases.issue(
            SystemFlowLease(
                flowType = "usageAccessSettings",
                expectedPackages = setOf("com.android.settings"),
                issuedElapsedMs = 1_900,
                expiresElapsedMs = 2_300,
            ),
        )

        assertNull(classifier.onForegroundResume(event("com.android.settings", 2_000)))
        assertNull(classifier.evaluate(2_700))

        val noLease = ForegroundTransitionClassifier(window)
        noLease.onForegroundResume(event("com.android.settings", 2_000))
        assertFailure(
            noLease.evaluate(2_600),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            2_000,
        )
    }

    @Test
    fun verifiedActiveCallPausesOnlyTheDefaultDialer() {
        val interruption =
            InterruptionSnapshot(
                isCallActive = true,
                defaultDialerPackage = "com.android.dialer",
            )
        val dialer = ForegroundTransitionClassifier(window)
        assertNull(
            dialer.onForegroundResume(
                event("com.android.dialer", 2_000),
                interruption,
            ),
        )
        assertNull(dialer.evaluate(2_700))

        val unverified = ForegroundTransitionClassifier(window)
        unverified.onForegroundResume(event("com.android.dialer", 2_000))
        assertFailure(
            unverified.evaluate(2_600),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            2_000,
        )
    }

    @Test
    fun duplicateAndOutOfOrderEventsDoNotResetDwell() {
        val classifier = ForegroundTransitionClassifier(window)
        val first = event("com.android.chrome", 2_000)

        assertNull(classifier.onForegroundResume(first))
        assertNull(classifier.onForegroundResume(first))
        assertNull(classifier.onForegroundResume(event("com.android.chrome", 900)))
        assertFailure(
            classifier.evaluate(2_600),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            2_000,
        )
    }

    @Test
    fun preDeadlineCandidateWinsEvenWhenDwellCrossesDeadline() {
        val classifier = ForegroundTransitionClassifier(window)

        assertNull(classifier.onForegroundResume(event("com.android.chrome", 9_800)))
        assertNull(classifier.evaluate(10_000))
        assertFailure(
            classifier.evaluate(10_400),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            9_800,
        )
    }

    @Test
    fun laterForeignResumeCannotReplaceAPreDeadlineCandidateWithSuccess() {
        val classifier = ForegroundTransitionClassifier(window)

        assertNull(classifier.onForegroundResume(event("com.android.chrome", 9_500)))
        assertFailure(
            classifier.onForegroundResume(event("com.example.video", 10_100)),
            TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            9_500,
        )
    }

    @Test
    fun eventAtDeadlineAndNoCandidateProduceOneDeadlineTerminal() {
        val atDeadline = ForegroundTransitionClassifier(window)
        assertDeadline(
            atDeadline.onForegroundResume(event("com.android.chrome", 10_000)),
        )
        assertDeadline(atDeadline.evaluate(11_000))

        val noCandidate = ForegroundTransitionClassifier(window)
        assertDeadline(noCandidate.evaluate(10_000))
    }

    @Test
    fun capabilityAndBootFailuresAreTerminalAndIdempotent() {
        val capability = ForegroundTransitionClassifier(window)
        assertFailure(
            capability.onCapabilityLost(2_000),
            TaskGuardFailureReason.MONITOR_CAPABILITY_LOST,
            2_000,
        )
        assertFailure(
            capability.onCapabilityLost(3_000),
            TaskGuardFailureReason.MONITOR_CAPABILITY_LOST,
            2_000,
        )

        val recovery = ForegroundTransitionClassifier(window)
        assertFailure(
            recovery.onBootDiscontinuity(2_000),
            TaskGuardFailureReason.RECOVERY_DETECTED_VIOLATION,
            2_000,
        )
    }

    private fun event(packageName: String, elapsedMs: Long): ForegroundResumeEvent {
        return ForegroundResumeEvent(
            packageName = packageName,
            className = "$packageName.MainActivity",
            eventWallTimeMs = 100_000 + elapsedMs,
            eventElapsedMs = elapsedMs,
        )
    }

    private fun assertFailure(
        terminal: TaskGuardTerminal?,
        reason: TaskGuardFailureReason,
        originElapsedMs: Long,
    ) {
        requireNotNull(terminal)
        assertEquals(TaskGuardTerminalKind.TASK_FAILED, terminal.kind)
        assertEquals(reason, terminal.failureReason)
        assertEquals(originElapsedMs, terminal.originElapsedMs)
    }

    private fun assertDeadline(terminal: TaskGuardTerminal?) {
        requireNotNull(terminal)
        assertEquals(TaskGuardTerminalKind.DEADLINE_REACHED, terminal.kind)
        assertNull(terminal.failureReason)
        assertEquals(10_000, terminal.originElapsedMs)
    }
}
