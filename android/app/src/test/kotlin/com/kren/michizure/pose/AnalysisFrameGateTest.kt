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
            AnalysisFrameDecision.BUSY,
            gate.tryAcquire(nowNs = 30_000_000, targetFps = 15),
        )
        assertEquals(
            AnalysisFrameDecision.BUSY,
            gate.tryAcquire(nowNs = 70_000_000, targetFps = 15),
        )
        gate.release()
        assertEquals(
            AnalysisFrameDecision.ACCEPTED,
            gate.tryAcquire(
                nowNs = 70_000_000,
                targetFps = 15,
                frameTimestampNs = 70_000_001,
            ),
        )
    }

    @Test
    fun invalidTimestampIsRejectedBeforeBusyAndThrottleChecks() {
        val gate = AnalysisFrameGate()
        assertEquals(
            AnalysisFrameDecision.ACCEPTED,
            gate.tryAcquire(nowNs = 0, targetFps = 4, frameTimestampNs = 100),
        )
        assertEquals(
            AnalysisFrameDecision.INVALID_TIMESTAMP,
            gate.tryAcquire(nowNs = 300_000_000, targetFps = 4, frameTimestampNs = 100),
        )
    }

    @Test
    fun emulatorThrottleDropsBeforeConversionAndAlwaysClosesFrame() {
        val dispatcher = AnalysisFrameDispatcher()
        var converted = 0
        var closed = 0
        val decisions = mutableListOf<AnalysisFrameDecision>()

        dispatcher.dispatch(0, 1, 4, { closed += 1 }, decisions::add) {
            converted += 1
            false
        }
        dispatcher.dispatch(249_999_999, 2, 4, { closed += 1 }, decisions::add) {
            converted += 1
            false
        }
        dispatcher.dispatch(250_000_000, 3, 4, { closed += 1 }, decisions::add) {
            converted += 1
            false
        }

        assertEquals(2, converted)
        assertEquals(3, closed)
        assertEquals(listOf(AnalysisFrameDecision.THROTTLED), decisions)
    }

    @Test
    fun busyFrameDoesNotConvertAndCallbackReleasesSingleInflightSlot() {
        val dispatcher = AnalysisFrameDispatcher()
        var converted = 0
        var closed = 0
        val decisions = mutableListOf<AnalysisFrameDecision>()

        dispatcher.dispatch(0, 1, 10, { closed += 1 }, decisions::add) {
            converted += 1
            true
        }
        dispatcher.dispatch(200_000_000, 2, 10, { closed += 1 }, decisions::add) {
            converted += 1
            false
        }
        dispatcher.completeInference()
        dispatcher.dispatch(200_000_000, 3, 10, { closed += 1 }, decisions::add) {
            converted += 1
            false
        }

        assertEquals(2, converted)
        assertEquals(3, closed)
        assertEquals(listOf(AnalysisFrameDecision.BUSY), decisions)
    }

    @Test
    fun conversionExceptionStillClosesFrameAndReleasesSlot() {
        val dispatcher = AnalysisFrameDispatcher()
        var closed = 0

        runCatching {
            dispatcher.dispatch(0, 1, 4, { closed += 1 }, {}) {
                error("conversion failed")
            }
        }
        dispatcher.dispatch(250_000_000, 2, 4, { closed += 1 }, {}) { false }

        assertEquals(2, closed)
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
