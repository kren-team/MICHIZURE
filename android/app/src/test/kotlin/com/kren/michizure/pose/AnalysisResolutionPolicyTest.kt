package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AnalysisResolutionPolicyTest {
    @Test
    fun prefersThreeHundredTwentyByTwoHundredFortyForEmulatorAnalysis() {
        val ordered =
            AnalysisResolutionPolicy.order(
                listOf(
                    ImageDimensions(1280, 960),
                    ImageDimensions(640, 480),
                    ImageDimensions(320, 240),
                ),
            )

        assertEquals(ImageDimensions(320, 240), ordered.first())
    }

    @Test
    fun fallsBackThroughExplicitLowResolutionOrder() {
        val ordered =
            AnalysisResolutionPolicy.order(
                listOf(
                    ImageDimensions(640, 480),
                    ImageDimensions(320, 180),
                    ImageDimensions(256, 192),
                    ImageDimensions(352, 288),
                ),
            )

        assertEquals(ImageDimensions(256, 192), ordered[0])
        assertEquals(ImageDimensions(320, 180), ordered[1])
        assertEquals(ImageDimensions(640, 480), ordered[2])
    }

    @Test
    fun handlesPortraitReportedAnalysisSizesWithoutChangingPriority() {
        val ordered =
            AnalysisResolutionPolicy.order(
                listOf(ImageDimensions(480, 640), ImageDimensions(240, 320)),
            )

        assertEquals(ImageDimensions(240, 320), ordered.first())
    }

    @Test
    fun statsExposeRequestedAndActualAnalysisResolutionOnlyAfterAFrame() {
        val stats = PosePipelineStats()
        stats.recordRequestedAnalysisResolution(320, 240)

        val requested = stats.snapshot()
        assertEquals(320, requested.requestedAnalysisWidth)
        assertEquals(240, requested.requestedAnalysisHeight)
        assertNull(requested.actualAnalysisWidth)
        assertNull(requested.actualAnalysisHeight)

        stats.recordActualAnalysisResolution(256, 192)
        val actual = stats.snapshot()
        assertEquals(256, actual.actualAnalysisWidth)
        assertEquals(192, actual.actualAnalysisHeight)
    }
}
