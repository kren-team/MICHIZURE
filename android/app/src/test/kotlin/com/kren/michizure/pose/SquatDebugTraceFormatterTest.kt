package com.kren.michizure.pose

import org.junit.Assert.assertTrue
import org.junit.Test

class SquatDebugTraceFormatterTest {
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
}
