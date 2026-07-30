package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Test

class AnalysisFrameGateTest {
    @Test
    fun throttlesBeforePreprocessingAndNeverQueuesWhileBusy() {
        val gate = AnalysisFrameGate()

        assertEquals(
            AnalysisFrameDecision.ACCEPTED,
            gate.tryAcquire(nowNs = 0, targetFps = 15),
        )
        assertEquals(
            AnalysisFrameDecision.THROTTLED,
            gate.tryAcquire(nowNs = 30_000_000, targetFps = 15),
        )
        assertEquals(
            AnalysisFrameDecision.BUSY,
            gate.tryAcquire(nowNs = 70_000_000, targetFps = 15),
        )
        gate.release()
        assertEquals(
            AnalysisFrameDecision.ACCEPTED,
            gate.tryAcquire(nowNs = 70_000_000, targetFps = 15),
        )
    }

    @Test
    fun duplicateReleaseAndResetAreIdempotent() {
        val gate = AnalysisFrameGate()
        gate.tryAcquire(0, 10)
        gate.release()
        gate.release()
        assertEquals(AnalysisFrameDecision.ACCEPTED, gate.tryAcquire(100_000_000, 10))
        gate.reset()
        assertEquals(AnalysisFrameDecision.ACCEPTED, gate.tryAcquire(1, 10))
    }
}
