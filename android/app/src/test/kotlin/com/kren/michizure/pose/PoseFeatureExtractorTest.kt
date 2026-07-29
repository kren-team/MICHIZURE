package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PoseFeatureExtractorTest {
    private val extractor = PoseFeatureExtractor()

    @Test
    fun extractsStraightLegAnglesAndNormalizedMeasurements() {
        val result = extractor.extract(frame(left = standingSide()))

        assertTrue(result is PoseFeatureResult.Valid)
        val sample = (result as PoseFeatureResult.Valid).sample
        assertEquals(180.0, sample.kneeAngleDeg, 0.001)
        assertEquals(180.0, sample.hipAngleDeg, 0.001)
        assertEquals(0.25, sample.hipY, 0.001)
        assertEquals(0.50, sample.legLength, 0.001)
        assertEquals(PoseSide.LEFT, sample.selectedSide)
    }

    @Test
    fun rejectsLowConfidenceAndPartialBody() {
        val lowConfidence =
            extractor.extract(
                frame(
                    left =
                        standingSide().copy(
                            ankle = PosePoint(50.0, 300.0, 0.4),
                        ),
                ),
            )
        assertEquals(
            PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE,
            (lowConfidence as PoseFeatureResult.Invalid).warning,
        )

        val tooSmall =
            extractor.extract(
                frame(
                    left =
                        BodySideLandmarks(
                            shoulder = PosePoint(50.0, 100.0, 0.9),
                            hip = PosePoint(50.0, 120.0, 0.9),
                            knee = PosePoint(50.0, 140.0, 0.9),
                            ankle = PosePoint(50.0, 160.0, 0.9),
                        ),
                ),
            )
        assertEquals(
            PoseQualityWarning.MOVE_CLOSER,
            (tooSmall as PoseFeatureResult.Invalid).warning,
        )
    }

    @Test
    fun averagesComparableLeftAndRightSides() {
        val result =
            extractor.extract(
                frame(
                    left = standingSide(confidence = 0.90),
                    right = standingSide(confidence = 0.85),
                ),
            ) as PoseFeatureResult.Valid

        assertEquals(PoseSide.BOTH, result.sample.selectedSide)
        assertEquals(0.85, result.sample.confidence, 0.001)
    }

    private fun frame(
        left: BodySideLandmarks?,
        right: BodySideLandmarks? = null,
    ) = PoseLandmarkFrame(
        timestampMs = 1_000,
        imageWidth = 400,
        imageHeight = 400,
        left = left,
        right = right,
    )

    private fun standingSide(confidence: Double = 0.9) =
        BodySideLandmarks(
            shoulder = PosePoint(50.0, 0.0, confidence),
            hip = PosePoint(50.0, 100.0, confidence),
            knee = PosePoint(50.0, 200.0, confidence),
            ankle = PosePoint(50.0, 300.0, confidence),
        )
}
