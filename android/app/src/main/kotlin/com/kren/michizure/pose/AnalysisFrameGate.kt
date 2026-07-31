package com.kren.michizure.pose

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class AnalysisFrameDecision {
    ACCEPTED,
    INVALID_TIMESTAMP,
    THROTTLED,
    BUSY,
}

class AnalysisFrameGate {
    private val inFlight = AtomicBoolean(false)
    private val lastSubmittedNs = AtomicLong(Long.MIN_VALUE)
    private val lastFrameTimestampNs = AtomicLong(Long.MIN_VALUE)

    fun tryAcquire(
        nowNs: Long,
        targetFps: Int,
        frameTimestampNs: Long = nowNs,
    ): AnalysisFrameDecision {
        require(targetFps > 0)
        while (true) {
            val previousFrameTimestampNs = lastFrameTimestampNs.get()
            if (previousFrameTimestampNs != Long.MIN_VALUE &&
                frameTimestampNs <= previousFrameTimestampNs
            ) {
                return AnalysisFrameDecision.INVALID_TIMESTAMP
            }
            if (lastFrameTimestampNs.compareAndSet(previousFrameTimestampNs, frameTimestampNs)) {
                break
            }
        }
        if (inFlight.get()) return AnalysisFrameDecision.BUSY
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
        lastFrameTimestampNs.set(Long.MIN_VALUE)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}

/**
 * Owns the pre-conversion admission boundary for an ImageAnalysis frame.
 *
 * [convertAndSubmit] is never invoked for invalid, busy, or throttled frames.
 * The caller-supplied close action runs exactly once for every dispatch path.
 * Returning true from [convertAndSubmit] keeps the single in-flight slot until
 * [completeInference] is called by the MediaPipe callback.
 */
class AnalysisFrameDispatcher(
    private val gate: AnalysisFrameGate = AnalysisFrameGate(),
) {
    fun dispatch(
        nowNs: Long,
        frameTimestampNs: Long,
        targetFps: Int,
        closeFrame: () -> Unit,
        onRejected: (AnalysisFrameDecision) -> Unit,
        convertAndSubmit: () -> Boolean,
    ) {
        var acquired = false
        var awaitingCallback = false
        try {
            val decision = gate.tryAcquire(nowNs, targetFps, frameTimestampNs)
            if (decision != AnalysisFrameDecision.ACCEPTED) {
                onRejected(decision)
                return
            }
            acquired = true
            awaitingCallback = convertAndSubmit()
        } finally {
            if (acquired && !awaitingCallback) gate.release()
            closeFrame()
        }
    }

    fun completeInference() = gate.release()

    fun reset() = gate.reset()
}
