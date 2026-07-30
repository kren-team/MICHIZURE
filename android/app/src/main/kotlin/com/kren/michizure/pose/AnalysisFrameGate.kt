package com.kren.michizure.pose

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class AnalysisFrameDecision {
    ACCEPTED,
    THROTTLED,
    BUSY,
}

class AnalysisFrameGate {
    private val inFlight = AtomicBoolean(false)
    private val lastSubmittedNs = AtomicLong(Long.MIN_VALUE)

    fun tryAcquire(
        nowNs: Long,
        targetFps: Int,
    ): AnalysisFrameDecision {
        require(targetFps > 0)
        val intervalNs = NANOS_PER_SECOND / targetFps
        val previous = lastSubmittedNs.get()
        if (previous != Long.MIN_VALUE && nowNs - previous < intervalNs) {
            return AnalysisFrameDecision.THROTTLED
        }
        if (!inFlight.compareAndSet(false, true)) {
            return AnalysisFrameDecision.BUSY
        }
        lastSubmittedNs.set(nowNs)
        return AnalysisFrameDecision.ACCEPTED
    }

    fun release() {
        inFlight.set(false)
    }

    fun reset() {
        inFlight.set(false)
        lastSubmittedNs.set(Long.MIN_VALUE)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
