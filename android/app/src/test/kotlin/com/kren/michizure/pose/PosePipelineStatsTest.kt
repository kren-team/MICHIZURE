package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Test

class PosePipelineStatsTest {
    @Test
    fun rollingMetricsUseOneMonotonicClockAndBoundTheirWindow() {
        val stats = PosePipelineStats(maxSamples = 3)
        repeat(4) { index ->
            val submitted = index * 100_000_000L
            stats.recordSubmitted(submitted)
            stats.recordResult(
                sample =
                    PoseLatencySample(
                        analyzerReceivedNs = submitted,
                        preprocessingStartedNs = submitted + 1_000_000,
                        inferenceSubmittedNs = submitted + 2_000_000,
                        inferenceCallbackNs = submitted + (12 + index) * 1_000_000,
                        stateMachineCompletedNs = submitted + (15 + index) * 1_000_000,
                        nativeEventDispatchedNs = null,
                    ),
                poseDetected = index != 2,
            )
        }

        val snapshot = stats.snapshot()

        assertEquals(3, snapshot.sampleCount)
        assertEquals(10.0, snapshot.actualAnalysisFps, 0.001)
        assertEquals(12L, snapshot.inferenceP50Ms)
        assertEquals(12L, snapshot.inferenceP95Ms)
        assertEquals(17L, snapshot.nativePipelineP50Ms)
        assertEquals(17L, snapshot.nativePipelineP95Ms)
        assertEquals(1L, snapshot.noPoseCount)
    }

    @Test
    fun dropAndBusyCountersResetWithoutRetainingPoseData() {
        val stats = PosePipelineStats()
        stats.recordDroppedBeforePreprocessing()
        stats.recordRejectedAsBusy()

        assertEquals(1, stats.snapshot().droppedBeforePreprocessing)
        assertEquals(1, stats.snapshot().rejectedAsBusy)

        stats.reset()

        assertEquals(PosePipelineMetrics(), stats.snapshot())
    }
}
