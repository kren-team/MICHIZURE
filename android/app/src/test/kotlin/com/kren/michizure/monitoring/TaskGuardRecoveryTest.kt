package com.kren.michizure.monitoring

import com.kren.michizure.persistence.NativeTaskEvent
import com.kren.michizure.persistence.NativeTaskEventType
import com.kren.michizure.persistence.NativeTaskRecord
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TaskGuardRecoveryTest {
    @Test
    fun lockedBootDefersCredentialProtectedTaskRead() = runBlocking {
        val store = FakeRecoveryStore(task = task())
        val service = FakeServiceControl()
        val recovery =
            TaskGuardRecovery(
                unlockState = UserUnlockState { false },
                store = store,
                service = service,
            )

        val result = recovery.reconcile()

        assertEquals(TaskGuardRecoveryResult.DEFERRED_UNTIL_UNLOCK, result)
        assertEquals(0, store.readCalls)
        assertEquals(0, service.startCalls)
    }

    @Test
    fun missingTaskStopsAStaleService() = runBlocking {
        val service = FakeServiceControl()
        val recovery =
            TaskGuardRecovery(
                unlockState = UserUnlockState { true },
                store = FakeRecoveryStore(task = null),
                service = service,
            )

        assertEquals(
            TaskGuardRecoveryResult.STOPPED_STALE_SERVICE,
            recovery.reconcile(),
        )
        assertEquals(1, service.stopCalls)
    }

    @Test
    fun pendingEventIsRetainedAndServiceIsNotRestarted() = runBlocking {
        val service = FakeServiceControl()
        val recovery =
            TaskGuardRecovery(
                unlockState = UserUnlockState { true },
                store =
                    FakeRecoveryStore(
                        task = task(),
                        event =
                            NativeTaskEvent(
                                eventId = "event-1",
                                taskSessionId = "task-1",
                                type = NativeTaskEventType.DEADLINE_REACHED,
                                occurredAtEpochMs = 2_000,
                                failureReason = null,
                            ),
                    ),
                service = service,
            )

        assertEquals(
            TaskGuardRecoveryResult.PENDING_EVENT_RETAINED,
            recovery.reconcile(),
        )
        assertEquals(0, service.startCalls)
        assertEquals(1, service.stopCalls)
    }

    @Test
    fun runningTaskStartsServiceAndDuplicateReconcileRemainsSafe() = runBlocking {
        val service = FakeServiceControl()
        val recovery =
            TaskGuardRecovery(
                unlockState = UserUnlockState { true },
                store = FakeRecoveryStore(task = task()),
                service = service,
            )

        assertEquals(TaskGuardRecoveryResult.STARTED, recovery.reconcile())
        assertEquals(TaskGuardRecoveryResult.STARTED, recovery.reconcile())
        assertEquals(2, service.startCalls)
        assertEquals(0, service.stopCalls)
    }

    @Test
    fun corruptedStoreDoesNotStartOrStopService() {
        val service = FakeServiceControl()
        val recovery =
            TaskGuardRecovery(
                unlockState = UserUnlockState { true },
                store = FakeRecoveryStore(error = IllegalStateException("corrupt")),
                service = service,
            )

        assertThrows(IllegalStateException::class.java) {
            runBlocking { recovery.reconcile() }
        }
        assertEquals(0, service.startCalls)
        assertEquals(0, service.stopCalls)
    }
}

private class FakeRecoveryStore(
    private val task: NativeTaskRecord? = null,
    private val event: NativeTaskEvent? = null,
    private val error: Throwable? = null,
) : TaskGuardRecoveryStore {
    var readCalls = 0

    override suspend fun readTask(): NativeTaskRecord? {
        readCalls += 1
        error?.let { throw it }
        return task
    }

    override suspend fun readPendingEvent(): NativeTaskEvent? {
        error?.let { throw it }
        return event
    }
}

private class FakeServiceControl : TaskGuardServiceControl {
    var startCalls = 0
    var stopCalls = 0

    override fun start() {
        startCalls += 1
    }

    override fun stop() {
        stopCalls += 1
    }
}

private fun task(): NativeTaskRecord {
    return NativeTaskRecord(
        taskSessionId = "task-1",
        startedWallMs = 1_000,
        expectedEndWallMs = 2_000,
        startedElapsedMs = 100,
        expectedEndElapsedMs = 1_100,
        bootCount = 1,
        guardConfigVersion = 1,
        lockTargetsAtStart = setOf("target.app"),
    )
}
