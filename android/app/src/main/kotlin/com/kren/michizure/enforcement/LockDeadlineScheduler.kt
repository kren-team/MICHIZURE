package com.kren.michizure.enforcement

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.kren.michizure.monitoring.TaskGuardRecovery
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

interface LockDeadlineScheduler {
    fun schedule(nextDeadlineElapsedMs: Long?)
}

class AndroidLockDeadlineScheduler(
    private val context: Context,
) : LockDeadlineScheduler {
    override fun schedule(nextDeadlineElapsedMs: Long?) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val operation = deadlineIntent(context)
        if (nextDeadlineElapsedMs == null) {
            alarmManager.cancel(operation)
            return
        }
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            nextDeadlineElapsedMs,
            operation,
        )
    }

    companion object {
        private const val REQUEST_CODE = 6106

        private fun deadlineIntent(context: Context): PendingIntent {
            return PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, LockReconcileReceiver::class.java)
                    .setAction(LockReconcileReceiver.ACTION_DEADLINE),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

class LockReconcileReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (intent.action !in supportedActions) {
            return
        }
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                // Lock and Task recovery are independent. One degraded feature
                // must not prevent the other from converging.
                runCatching {
                    LockCoordinator(context.applicationContext).reconcile()
                }
                if (intent.action in taskRecoveryActions) {
                    runCatching {
                        TaskGuardRecovery(context.applicationContext).reconcile()
                    }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        const val ACTION_DEADLINE = "com.kren.michizure.action.LOCK_DEADLINE"
        private val supportedActions =
            setOf(
                ACTION_DEADLINE,
                Intent.ACTION_LOCKED_BOOT_COMPLETED,
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_USER_UNLOCKED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
                Intent.ACTION_PACKAGE_ADDED,
                Intent.ACTION_PACKAGE_REMOVED,
                Intent.ACTION_PACKAGE_REPLACED,
            )
        private val taskRecoveryActions =
            setOf(
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_USER_UNLOCKED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
            )
    }
}
