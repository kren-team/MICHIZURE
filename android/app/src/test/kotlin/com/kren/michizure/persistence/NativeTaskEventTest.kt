package com.kren.michizure.persistence

import com.kren.michizure.monitoring.TaskGuardFailureReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class NativeTaskEventTest {
    @Test
    fun failurePayloadIsVersionedAndContainsNoPackageInformation() {
        val event =
            NativeTaskEvent(
                eventId = "event-1",
                taskSessionId = "task-1",
                type = NativeTaskEventType.TASK_FAILED,
                occurredAtEpochMs = 1_000,
                failureReason = TaskGuardFailureReason.FOREIGN_APP_FOREGROUND,
            )

        val payload = event.toWirePayload()

        assertEquals(1, payload["contractVersion"])
        assertEquals("taskFailed", payload["eventType"])
        assertEquals("foreign_app_foreground", payload["reason"])
        assertFalse(payload.containsKey("packageName"))
        assertFalse(payload.containsKey("detectedPackageName"))
    }

    @Test
    fun deadlinePayloadHasNoFailureReason() {
        val event =
            NativeTaskEvent(
                eventId = "event-2",
                taskSessionId = "task-1",
                type = NativeTaskEventType.DEADLINE_REACHED,
                occurredAtEpochMs = 2_000,
                failureReason = null,
            )

        assertNull(event.toWirePayload()["reason"])
    }
}
