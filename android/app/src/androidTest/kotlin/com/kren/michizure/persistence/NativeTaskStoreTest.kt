package com.kren.michizure.persistence

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.kren.michizure.monitoring.TaskGuardFailureReason
import com.kren.michizure.monitoring.TaskGuardTerminal
import com.kren.michizure.monitoring.TaskGuardTerminalKind
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeTaskStoreTest {
    private val context =
        ApplicationProvider.getApplicationContext<android.content.Context>()
    private val store = NativeTaskStore(context)

    @Test
    fun duplicateStartAndTerminalDeliveryAreIdempotent() = runBlocking {
        val taskId = "task-${System.nanoTime()}"
        val first = record(taskId)
        store.start(first)

        val duplicate =
            store.start(
                first.copy(
                    startedElapsedMs = first.startedElapsedMs + 50,
                    expectedEndElapsedMs = first.expectedEndElapsedMs + 50,
                ),
            )
        assertEquals(first, duplicate)

        val terminal =
            TaskGuardTerminal(
                kind = TaskGuardTerminalKind.TASK_FAILED,
                failureReason = TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
                originElapsedMs = first.startedElapsedMs + 200,
            )
        val event = store.commitTerminal(taskId, terminal)
        val duplicateEvent =
            store.commitTerminal(
                taskId,
                terminal.copy(originElapsedMs = first.startedElapsedMs + 400),
            )

        assertEquals(event, duplicateEvent)
        assertEquals(event, store.readPendingEvent())
        assertEquals(first.startedWallMs + 200, event.occurredAtEpochMs)
        assertTrue(store.acknowledge(event.eventId))
        assertNull(store.readTask())
        assertNull(store.readPendingEvent())
        assertFalse(store.acknowledge(event.eventId))
    }

    @Test
    fun manualStopIsDuplicateSafe() = runBlocking {
        val taskId = "task-${System.nanoTime()}"
        store.start(record(taskId))

        assertTrue(store.stop(taskId))
        assertFalse(store.stop(taskId))
    }

    @Test
    fun separateTaskCannotReplaceAnActiveRecord() = runBlocking {
        val firstId = "task-${System.nanoTime()}"
        val secondId = "$firstId-other"
        store.start(record(firstId))

        val error =
            runCatching { store.start(record(secondId)) }.exceptionOrNull()

        require(error is NativeTaskStoreException)
        assertEquals("activeTaskConflict", error.code)
        assertNotEquals(secondId, store.readTask()?.taskSessionId)
        assertTrue(store.stop(firstId))
    }

    private fun record(taskId: String): NativeTaskRecord {
        return NativeTaskRecord(
            taskSessionId = taskId,
            startedWallMs = 10_000,
            expectedEndWallMs = 70_000,
            startedElapsedMs = 1_000,
            expectedEndElapsedMs = 61_000,
            bootCount = 1,
            guardConfigVersion = 1,
            lockTargetsAtStart = setOf("example.target"),
        )
    }
}
