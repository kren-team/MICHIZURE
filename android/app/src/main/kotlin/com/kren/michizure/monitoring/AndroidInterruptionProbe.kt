package com.kren.michizure.monitoring

import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager

class AndroidInterruptionProbe(context: Context) {
    private val powerManager = context.getSystemService(PowerManager::class.java)
    private val keyguardManager = context.getSystemService(KeyguardManager::class.java)

    fun snapshot(): InterruptionSnapshot {
        return InterruptionSnapshot(
            isInteractive = powerManager?.isInteractive != false,
            isKeyguardLocked = keyguardManager?.isKeyguardLocked == true,
            // Emulator MVP intentionally adds no phone-state permission. A dialer is
            // exempt only when a future consented signal can prove an active call.
            isCallActive = false,
            defaultDialerPackage = null,
        )
    }
}
