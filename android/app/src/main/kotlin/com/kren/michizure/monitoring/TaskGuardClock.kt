package com.kren.michizure.monitoring

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

interface TaskGuardClock {
    fun wallTimeMs(): Long

    fun elapsedRealtimeMs(): Long

    fun bootCount(): Int
}

class AndroidTaskGuardClock(private val context: Context) : TaskGuardClock {
    override fun wallTimeMs(): Long = System.currentTimeMillis()

    override fun elapsedRealtimeMs(): Long = SystemClock.elapsedRealtime()

    override fun bootCount(): Int {
        return Settings.Global.getInt(
            context.contentResolver,
            Settings.Global.BOOT_COUNT,
            0,
        )
    }
}
