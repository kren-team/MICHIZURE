package com.kren.michizure.monitoring

import android.content.Context
import android.os.Build
import android.os.UserManager
import com.kren.michizure.persistence.NativeTaskEvent
import com.kren.michizure.persistence.NativeTaskRecord
import com.kren.michizure.persistence.NativeTaskStore

enum class TaskGuardRecoveryResult {
    DEFERRED_UNTIL_UNLOCK,
    STOPPED_STALE_SERVICE,
    PENDING_EVENT_RETAINED,
    STARTED,
}

class TaskGuardRecovery(
    private val unlockState: UserUnlockState,
    private val store: TaskGuardRecoveryStore,
    private val service: TaskGuardServiceControl,
) {
    constructor(context: Context) : this(
        unlockState = AndroidUserUnlockState(context),
        store = StoredTaskGuardRecoveryStore(NativeTaskStore(context)),
        service = AndroidTaskGuardServiceControl(context),
    )

    suspend fun reconcile(): TaskGuardRecoveryResult {
        if (!unlockState.isUserUnlocked()) {
            return TaskGuardRecoveryResult.DEFERRED_UNTIL_UNLOCK
        }
        val task = store.readTask()
        if (task == null) {
            service.stop()
            return TaskGuardRecoveryResult.STOPPED_STALE_SERVICE
        }
        if (store.readPendingEvent() != null) {
            service.stop()
            return TaskGuardRecoveryResult.PENDING_EVENT_RETAINED
        }
        service.start()
        return TaskGuardRecoveryResult.STARTED
    }
}

fun interface UserUnlockState {
    fun isUserUnlocked(): Boolean
}

interface TaskGuardRecoveryStore {
    suspend fun readTask(): NativeTaskRecord?

    suspend fun readPendingEvent(): NativeTaskEvent?
}

interface TaskGuardServiceControl {
    fun start()

    fun stop()
}

private class AndroidUserUnlockState(
    private val context: Context,
) : UserUnlockState {
    override fun isUserUnlocked(): Boolean {
        if (Build.VERSION.SDK_INT < 24) {
            return true
        }
        return context.getSystemService(UserManager::class.java)?.isUserUnlocked == true
    }
}

private class StoredTaskGuardRecoveryStore(
    private val store: NativeTaskStore,
) : TaskGuardRecoveryStore {
    override suspend fun readTask(): NativeTaskRecord? = store.readTask()

    override suspend fun readPendingEvent(): NativeTaskEvent? = store.readPendingEvent()
}

private class AndroidTaskGuardServiceControl(
    private val context: Context,
) : TaskGuardServiceControl {
    override fun start() {
        TaskGuardService.start(context)
    }

    override fun stop() {
        TaskGuardService.stop(context)
    }
}
