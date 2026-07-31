package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Test

class PosePipelineStatsTest {
    @Test
    fun rollingMetricsUseOneMonotonicClockAndBoundTheirWindow() {
        val stats = PosePipelineStats(maxSamples = 3)
        repeat(4) { index ->
            val submitted = index * 100_000_000L
            stats.recordSubmitted(
                timestampNs = submitted,
                preprocessingDurationMs = 2,
                delegate = PoseDelegate.CPU,
            )
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
        assertEquals(4L, snapshot.inferenceSubmitted)
        assertEquals(4L, snapshot.resultCallbacks)
        assertEquals(3L, snapshot.resultsWithPose)
        assertEquals(1L, snapshot.resultsWithoutPose)
        assertEquals(2L, snapshot.preprocessingP50Ms)
        assertEquals(PoseDelegate.CPU, snapshot.activeDelegate)
        assertEquals(1L, snapshot.noPoseCount)
    }

    @Test
    fun callbackAgeDistinguishesNoCallbackFromNoPoseCallback() {
        val stats = PosePipelineStats()
        stats.setDelegate(PoseDelegate.CPU)
        stats.recordSubmitted(
            timestampNs = 1_000_000_000,
            preprocessingDurationMs = 4,
            delegate = PoseDelegate.CPU,
        )

        val beforeCallback = stats.snapshot(nowNs = 3_100_000_000)
        assertEquals(0L, beforeCallback.resultCallbacks)
        assertEquals(2_100L, beforeCallback.lastCallbackAgeMs)

        stats.recordResult(
            sample =
                PoseLatencySample(
                    analyzerReceivedNs = 3_000_000_000,
                    preprocessingStartedNs = 3_001_000_000,
                    inferenceSubmittedNs = 3_004_000_000,
                    inferenceCallbackNs = 3_050_000_000,
                    stateMachineCompletedNs = 3_052_000_000,
                    nativeEventDispatchedNs = null,
                ),
            poseDetected = false,
        )

        val afterNoPoseCallback = stats.snapshot(nowNs = 3_100_000_000)
        assertEquals(1L, afterNoPoseCallback.resultCallbacks)
        assertEquals(0L, afterNoPoseCallback.resultsWithPose)
        assertEquals(1L, afterNoPoseCallback.resultsWithoutPose)
        assertEquals(50L, afterNoPoseCallback.lastCallbackAgeMs)
        assertEquals(46L, afterNoPoseCallback.inferenceP50Ms)
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
