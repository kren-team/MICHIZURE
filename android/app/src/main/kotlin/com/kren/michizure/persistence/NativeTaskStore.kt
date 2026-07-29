package com.kren.michizure.persistence

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.kren.michizure.monitoring.TaskGuardFailureReason
import com.kren.michizure.monitoring.TaskGuardTerminal
import com.kren.michizure.monitoring.TaskGuardTerminalKind
import kotlinx.coroutines.flow.first
import java.util.UUID

private val Context.nativeTaskDataStore by preferencesDataStore(
    name = "native_task_guard",
)

data class NativeTaskRecord(
    val taskSessionId: String,
    val startedWallMs: Long,
    val expectedEndWallMs: Long,
    val startedElapsedMs: Long,
    val expectedEndElapsedMs: Long,
    val bootCount: Int,
    val guardConfigVersion: Int,
    val lockTargetsAtStart: Set<String>,
)

enum class NativeTaskEventType(val wireValue: String) {
    TASK_FAILED("taskFailed"),
    DEADLINE_REACHED("deadlineReached"),
}

data class NativeTaskEvent(
    val eventId: String,
    val taskSessionId: String,
    val type: NativeTaskEventType,
    val occurredAtEpochMs: Long,
    val failureReason: TaskGuardFailureReason?,
) {
    fun toWirePayload(): Map<String, Any?> {
        return mapOf(
            "contractVersion" to CONTRACT_VERSION,
            "eventId" to eventId,
            "taskSessionId" to taskSessionId,
            "eventType" to type.wireValue,
            "occurredAtEpochMs" to occurredAtEpochMs,
            "reason" to failureReason?.wireValue,
        )
    }

    companion object {
        const val CONTRACT_VERSION = 1
    }
}

class NativeTaskStore(context: Context) {
    private val dataStore = context.nativeTaskDataStore

    suspend fun readTask(): NativeTaskRecord? {
        return decodeTask(dataStore.data.first())
    }

    suspend fun readPendingEvent(): NativeTaskEvent? {
        return decodePendingEvent(dataStore.data.first())
    }

    suspend fun start(record: NativeTaskRecord): NativeTaskRecord {
        validate(record)
        var resolved = record
        dataStore.edit { preferences ->
            val existing = decodeTask(preferences)
            if (existing != null) {
                if (existing.taskSessionId != record.taskSessionId) {
                    throw NativeTaskStoreException("activeTaskConflict")
                }
                resolved = existing
                return@edit
            }
            writeTask(preferences, record)
            clearPendingEvent(preferences)
        }
        return resolved
    }

    suspend fun commitTerminal(
        taskSessionId: String,
        terminal: TaskGuardTerminal,
    ): NativeTaskEvent {
        var committed: NativeTaskEvent? = null
        dataStore.edit { preferences ->
            val record =
                decodeTask(preferences)
                    ?: throw NativeTaskStoreException("missingTask")
            if (record.taskSessionId != taskSessionId) {
                throw NativeTaskStoreException("taskMismatch")
            }
            val existing = decodePendingEvent(preferences)
            if (existing != null) {
                committed = existing
                return@edit
            }
            val occurredAtEpochMs =
                record.startedWallMs +
                    (terminal.originElapsedMs - record.startedElapsedMs)
            val event =
                NativeTaskEvent(
                    eventId = UUID.randomUUID().toString(),
                    taskSessionId = taskSessionId,
                    type =
                        when (terminal.kind) {
                            TaskGuardTerminalKind.TASK_FAILED ->
                                NativeTaskEventType.TASK_FAILED
                            TaskGuardTerminalKind.DEADLINE_REACHED ->
                                NativeTaskEventType.DEADLINE_REACHED
                        },
                    occurredAtEpochMs = occurredAtEpochMs,
                    failureReason = terminal.failureReason,
                )
            writePendingEvent(preferences, event)
            committed = event
        }
        return checkNotNull(committed)
    }

    suspend fun acknowledge(eventId: String): Boolean {
        var acknowledged = false
        dataStore.edit { preferences ->
            val event = decodePendingEvent(preferences)
            if (event?.eventId == eventId) {
                clearAll(preferences)
                acknowledged = true
            }
        }
        return acknowledged
    }

    suspend fun stop(taskSessionId: String): Boolean {
        var stopped = false
        dataStore.edit { preferences ->
            val record = decodeTask(preferences)
            if (record == null) {
                return@edit
            }
            if (record.taskSessionId != taskSessionId) {
                throw NativeTaskStoreException("taskMismatch")
            }
            clearAll(preferences)
            stopped = true
        }
        return stopped
    }

    private fun decodeTask(preferences: Preferences): NativeTaskRecord? {
        if (preferences[hasTaskKey] != true) {
            return null
        }
        val taskSessionId = preferences[taskSessionIdKey]
        val startedWallMs = preferences[startedWallMsKey]
        val expectedEndWallMs = preferences[expectedEndWallMsKey]
        val startedElapsedMs = preferences[startedElapsedMsKey]
        val expectedEndElapsedMs = preferences[expectedEndElapsedMsKey]
        val bootCount = preferences[bootCountKey]
        val guardConfigVersion = preferences[guardConfigVersionKey]
        val lockTargets = preferences[lockTargetsKey]
        if (taskSessionId.isNullOrBlank() ||
            startedWallMs == null ||
            expectedEndWallMs == null ||
            startedElapsedMs == null ||
            expectedEndElapsedMs == null ||
            bootCount == null ||
            guardConfigVersion == null ||
            lockTargets == null
        ) {
            throw NativeTaskStoreException("corruptTask")
        }
        return NativeTaskRecord(
            taskSessionId = taskSessionId,
            startedWallMs = startedWallMs,
            expectedEndWallMs = expectedEndWallMs,
            startedElapsedMs = startedElapsedMs,
            expectedEndElapsedMs = expectedEndElapsedMs,
            bootCount = bootCount,
            guardConfigVersion = guardConfigVersion,
            lockTargetsAtStart = lockTargets.toSet(),
        ).also(::validate)
    }

    private fun decodePendingEvent(preferences: Preferences): NativeTaskEvent? {
        if (preferences[hasPendingEventKey] != true) {
            return null
        }
        val eventId = preferences[eventIdKey]
        val taskSessionId = preferences[eventTaskSessionIdKey]
        val eventType = preferences[eventTypeKey]
            ?.let { wire -> NativeTaskEventType.entries.firstOrNull { it.wireValue == wire } }
        val occurredAtEpochMs = preferences[eventOccurredAtKey]
        val reasonWire = preferences[eventFailureReasonKey]
        val reason =
            reasonWire?.let { wire ->
                TaskGuardFailureReason.entries.firstOrNull { it.wireValue == wire }
                    ?: throw NativeTaskStoreException("corruptEvent")
            }
        if (eventId.isNullOrBlank() ||
            taskSessionId.isNullOrBlank() ||
            eventType == null ||
            occurredAtEpochMs == null ||
            (eventType == NativeTaskEventType.TASK_FAILED && reason == null) ||
            (eventType == NativeTaskEventType.DEADLINE_REACHED && reason != null)
        ) {
            throw NativeTaskStoreException("corruptEvent")
        }
        return NativeTaskEvent(
            eventId = eventId,
            taskSessionId = taskSessionId,
            type = eventType,
            occurredAtEpochMs = occurredAtEpochMs,
            failureReason = reason,
        )
    }

    private fun writeTask(
        preferences: androidx.datastore.preferences.core.MutablePreferences,
        record: NativeTaskRecord,
    ) {
        preferences[hasTaskKey] = true
        preferences[taskSessionIdKey] = record.taskSessionId
        preferences[startedWallMsKey] = record.startedWallMs
        preferences[expectedEndWallMsKey] = record.expectedEndWallMs
        preferences[startedElapsedMsKey] = record.startedElapsedMs
        preferences[expectedEndElapsedMsKey] = record.expectedEndElapsedMs
        preferences[bootCountKey] = record.bootCount
        preferences[guardConfigVersionKey] = record.guardConfigVersion
        preferences[lockTargetsKey] = record.lockTargetsAtStart
    }

    private fun writePendingEvent(
        preferences: androidx.datastore.preferences.core.MutablePreferences,
        event: NativeTaskEvent,
    ) {
        preferences[hasPendingEventKey] = true
        preferences[eventIdKey] = event.eventId
        preferences[eventTaskSessionIdKey] = event.taskSessionId
        preferences[eventTypeKey] = event.type.wireValue
        preferences[eventOccurredAtKey] = event.occurredAtEpochMs
        if (event.failureReason == null) {
            preferences.remove(eventFailureReasonKey)
        } else {
            preferences[eventFailureReasonKey] = event.failureReason.wireValue
        }
    }

    private fun clearPendingEvent(
        preferences: androidx.datastore.preferences.core.MutablePreferences,
    ) {
        preferences.remove(hasPendingEventKey)
        preferences.remove(eventIdKey)
        preferences.remove(eventTaskSessionIdKey)
        preferences.remove(eventTypeKey)
        preferences.remove(eventOccurredAtKey)
        preferences.remove(eventFailureReasonKey)
    }

    private fun clearAll(
        preferences: androidx.datastore.preferences.core.MutablePreferences,
    ) {
        preferences.clear()
    }

    private fun validate(record: NativeTaskRecord) {
        if (record.taskSessionId.isBlank() ||
            record.startedWallMs < 0 ||
            record.expectedEndWallMs < record.startedWallMs ||
            record.startedElapsedMs < 0 ||
            record.expectedEndElapsedMs < record.startedElapsedMs ||
            record.bootCount < 0 ||
            record.guardConfigVersion != 1 ||
            record.lockTargetsAtStart.isEmpty() ||
            record.lockTargetsAtStart.any(String::isBlank)
        ) {
            throw NativeTaskStoreException("invalidTask")
        }
    }

    companion object {
        private val hasTaskKey = booleanPreferencesKey("has_task_v1")
        private val taskSessionIdKey = stringPreferencesKey("task_session_id_v1")
        private val startedWallMsKey = longPreferencesKey("started_wall_ms_v1")
        private val expectedEndWallMsKey = longPreferencesKey("expected_end_wall_ms_v1")
        private val startedElapsedMsKey = longPreferencesKey("started_elapsed_ms_v1")
        private val expectedEndElapsedMsKey =
            longPreferencesKey("expected_end_elapsed_ms_v1")
        private val bootCountKey = intPreferencesKey("boot_count_v1")
        private val guardConfigVersionKey = intPreferencesKey("guard_config_version_v1")
        private val lockTargetsKey = stringSetPreferencesKey("lock_targets_v1")
        private val hasPendingEventKey = booleanPreferencesKey("has_pending_event_v1")
        private val eventIdKey = stringPreferencesKey("event_id_v1")
        private val eventTaskSessionIdKey = stringPreferencesKey("event_task_id_v1")
        private val eventTypeKey = stringPreferencesKey("event_type_v1")
        private val eventOccurredAtKey = longPreferencesKey("event_occurred_at_v1")
        private val eventFailureReasonKey = stringPreferencesKey("event_reason_v1")
    }
}

class NativeTaskStoreException(val code: String) : IllegalStateException(code)
