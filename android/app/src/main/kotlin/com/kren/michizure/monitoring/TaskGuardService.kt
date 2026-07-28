package com.kren.michizure.monitoring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.kren.michizure.MainActivity
import com.kren.michizure.persistence.NativeTaskEvent
import com.kren.michizure.persistence.NativeTaskRecord
import com.kren.michizure.persistence.NativeTaskStore
import com.kren.michizure.platform.TaskEventBus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class TaskGuardService : Service() {
    private val serviceScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var monitorJob: Job? = null

    private lateinit var store: NativeTaskStore
    private lateinit var clock: TaskGuardClock
    private lateinit var eventSource: UsageEventSource
    private lateinit var interruptionProbe: AndroidInterruptionProbe

    override fun onCreate() {
        super.onCreate()
        store = NativeTaskStore(applicationContext)
        clock = AndroidTaskGuardClock(applicationContext)
        eventSource = AndroidUsageEventSource(applicationContext)
        interruptionProbe = AndroidInterruptionProbe(applicationContext)
        createNotificationChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (!promoteToForeground()) {
            commitCapabilityFailureAndStop()
            return START_NOT_STICKY
        }
        if (monitorJob?.isActive != true) {
            monitorJob = serviceScope.launch { monitorPersistedTask() }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        monitorJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private suspend fun monitorPersistedTask() {
        val record =
            runCatching { store.readTask() }.getOrElse {
                stopGuardService()
                return
            } ?: run {
                stopGuardService()
                return
            }
        if (store.readPendingEvent() != null) {
            stopGuardService()
            return
        }

        val classifier =
            ForegroundTransitionClassifier(
                TaskGuardWindow(
                    taskSessionId = record.taskSessionId,
                    ownPackageName = packageName,
                    startedElapsedMs = record.startedElapsedMs,
                    expectedEndElapsedMs = record.expectedEndElapsedMs,
                ),
            )
        if (record.bootCount != clock.bootCount()) {
            val terminal =
                if (clock.wallTimeMs() >= record.expectedEndWallMs) {
                    classifier.evaluate(record.expectedEndElapsedMs)
                        ?: classifier.onBootDiscontinuity(clock.elapsedRealtimeMs())
                } else {
                    classifier.onBootDiscontinuity(clock.elapsedRealtimeMs())
                }
            persistAndEmit(record, terminal)
            return
        }

        var cursorWallMs = record.startedWallMs
        while (serviceScope.isActive) {
            val nowWallMs = clock.wallTimeMs()
            val nowElapsedMs = clock.elapsedRealtimeMs()
            val queryStart = (cursorWallMs - QUERY_OVERLAP_MS)
                .coerceAtLeast(record.startedWallMs)
            val queryResult = eventSource.queryResumedEvents(queryStart, nowWallMs + 1)
            val terminal =
                when (queryResult) {
                    is UsageEventQueryResult.Available -> {
                        var result: TaskGuardTerminal? = null
                        queryResult.events.sortedBy { it.timestampWallMs }.forEach { event ->
                            cursorWallMs = maxOf(cursorWallMs, event.timestampWallMs)
                            if (result == null) {
                                val eventElapsedMs =
                                    nowElapsedMs - (nowWallMs - event.timestampWallMs)
                                result =
                                    classifier.onForegroundResume(
                                        ForegroundResumeEvent(
                                            packageName = event.packageName,
                                            className = event.className,
                                            eventWallTimeMs = event.timestampWallMs,
                                            eventElapsedMs = eventElapsedMs,
                                        ),
                                        interruptionProbe.snapshot(),
                                    )
                            }
                        }
                        result ?: classifier.evaluate(
                            nowElapsedMs,
                            interruptionProbe.snapshot(),
                        )
                    }
                    UsageEventQueryResult.CapabilityMissing,
                    UsageEventQueryResult.Unavailable,
                    -> classifier.onCapabilityLost(nowElapsedMs)
                }
            if (terminal != null) {
                persistAndEmit(record, terminal)
                return
            }
            cursorWallMs = maxOf(cursorWallMs, nowWallMs)
            delay(POLL_INTERVAL_MS)
        }
    }

    private suspend fun persistAndEmit(
        record: NativeTaskRecord,
        terminal: TaskGuardTerminal,
    ) {
        val event =
            runCatching {
                store.commitTerminal(record.taskSessionId, terminal)
            }.getOrNull()
        if (event != null) {
            TaskEventBus.emit(event)
        }
        stopGuardService()
    }

    private fun commitCapabilityFailureAndStop() {
        serviceScope.launch(Dispatchers.IO) {
            val record = runCatching { store.readTask() }.getOrNull()
            if (record != null) {
                val terminal =
                    TaskGuardTerminal(
                        kind = TaskGuardTerminalKind.TASK_FAILED,
                        failureReason = TaskGuardFailureReason.MONITOR_CAPABILITY_LOST,
                        originElapsedMs = clock.elapsedRealtimeMs(),
                    )
                runCatching { store.commitTerminal(record.taskSessionId, terminal) }
                    .getOrNull()
                    ?.let(TaskEventBus::emit)
            }
            stopSelf()
        }
    }

    private fun promoteToForeground(): Boolean {
        return runCatching {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.isSuccess
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Task monitoring",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "MICHIZUREが実行中のTaskを監視していることを表示します"
                setShowBadge(false)
            },
        )
    }

    private fun buildNotification(): Notification {
        val openAppIntent =
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val builder =
            if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Taskを監視中")
            .setContentText("MICHIZUREとの約束を守るため、端末内で画面遷移を確認しています")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun stopGuardService() {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    companion object {
        const val POLL_INTERVAL_MS = 250L
        const val QUERY_OVERLAP_MS = 1_000L
        const val NOTIFICATION_CHANNEL_ID = "task_guard_v1"
        const val NOTIFICATION_ID = 4105

        fun start(context: Context) {
            val intent = Intent(context, TaskGuardService::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TaskGuardService::class.java))
        }
    }
}
