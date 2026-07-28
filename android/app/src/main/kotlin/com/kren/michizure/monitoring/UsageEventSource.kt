package com.kren.michizure.monitoring

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process

sealed interface UsageEventQueryResult {
    data class Available(val events: List<UsageResumeEvent>) : UsageEventQueryResult

    data object CapabilityMissing : UsageEventQueryResult

    data object Unavailable : UsageEventQueryResult
}

data class UsageResumeEvent(
    val packageName: String,
    val className: String,
    val timestampWallMs: Long,
)

interface UsageEventSource {
    fun queryResumedEvents(beginWallMs: Long, endWallMs: Long): UsageEventQueryResult
}

class AndroidUsageEventSource(private val context: Context) : UsageEventSource {
    private val usageStatsManager =
        context.getSystemService(UsageStatsManager::class.java)
    private val appOpsManager =
        context.getSystemService(AppOpsManager::class.java)

    override fun queryResumedEvents(
        beginWallMs: Long,
        endWallMs: Long,
    ): UsageEventQueryResult {
        if (!hasUsageAccess()) {
            return UsageEventQueryResult.CapabilityMissing
        }
        val manager = usageStatsManager ?: return UsageEventQueryResult.Unavailable
        val usageEvents =
            runCatching {
                manager.queryEvents(beginWallMs.coerceAtLeast(0), endWallMs)
            }.getOrNull() ?: return UsageEventQueryResult.Unavailable
        val result = mutableListOf<UsageResumeEvent>()
        val event = UsageEvents.Event()
        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                val packageName = event.packageName
                if (!packageName.isNullOrBlank()) {
                    result +=
                        UsageResumeEvent(
                            packageName = packageName,
                            className = event.className.orEmpty(),
                            timestampWallMs = event.timeStamp,
                        )
                }
            }
        }
        return UsageEventQueryResult.Available(result)
    }

    @Suppress("DEPRECATION")
    private fun hasUsageAccess(): Boolean {
        val appOps = appOpsManager ?: return false
        return appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }
}
