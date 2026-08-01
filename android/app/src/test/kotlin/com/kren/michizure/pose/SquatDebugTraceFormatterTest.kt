package com.kren.michizure.pose

import org.junit.Assert.assertTrue
import org.junit.Test

class SquatDebugTraceFormatterTest {
    @Test
    fun squatTraceIncludesCalibrationFallbackDetails() {
        val detector = SquatStateMachine()
        detector.process(validSample(0, 171.1))
        val update = detector.process(validSample(500, 176.7))

        val line = SquatDebugTraceFormatter.trace(update, PosePipelineMetrics())

        assertTrue(line.contains("candidateCount=2"))
        assertTrue(line.contains("strongCandidates=2"))
        assertTrue(line.contains("provisional=176.7"))
        assertTrue(line.contains("calMedian=173.9"))
        assertTrue(line.contains("baselineSource=TWO_SAMPLE_MEDIAN"))
    }

    @Test
    fun performanceTraceContainsOnlyBoundedAggregateMetrics() {
        val line =
            SquatDebugTraceFormatter.performance(
                PosePipelineMetrics(
                    analyzerInputFps = 30.0,
                    inferenceSubmittedFps = 4.0,
                    resultCallbackFps = 3.8,
                    validPoseFps = 3.6,
                    droppedBeforePreprocessing = 20,
                    rejectedAsBusy = 6,
                    convertedBitmapCount = 4,
                    rotationBitmapCount = 4,
                    preprocessingP95Ms = 8,
                    inferenceP95Ms = 180,
                    nativePipelineP95Ms = 195,
                ),
            )

        assertTrue(line.contains("inputFps=30.0"))
        assertTrue(line.contains("submitFps=4.0"))
        assertTrue(line.contains("converted=4"))
        assertTrue(line.contains("rotated=4"))
        assertTrue(line.contains("pipelineP95Ms=195"))
    }

    private fun validSample(timestampMs: Long, knee: Double) =
        PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = timestampMs,
                    kneeAngleDeg = knee,
                    hipY = 0.25,
                    legLength = 0.50,
                    confidence = 0.90,
                    selectedSide = PoseSide.LEFT,
                ),
            quality =
                PoseQualityMetrics.EMPTY.copy(
                    poseDetected = true,
                    selectedSide = PoseSide.LEFT,
                    trackingStatus = PoseTrackingStatus.VALID,
                ),
        )
}
