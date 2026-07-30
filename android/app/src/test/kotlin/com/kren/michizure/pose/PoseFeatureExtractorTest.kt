package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PoseFeatureExtractorTest {
    private val extractor = PoseFeatureExtractor()

    @Test
    fun lowerBodyOnlyNeedsNoFaceShoulderOrUpperBody() {
        val result = extractor.extract(pose(left = standingSide()))

        assertTrue(result is PoseFeatureResult.Valid)
        val sample = (result as PoseFeatureResult.Valid).sample
        assertEquals(180.0, sample.kneeAngleDeg, 0.001)
        assertEquals(0.25, sample.hipY, 0.001)
        assertEquals(0.50, sample.legLength, 0.001)
        assertEquals(PoseSide.LEFT, sample.selectedSide)
    }

    @Test
    fun eitherLeftOrRightLegCanPassTheQualityGate() {
        val left = extractor.extract(pose(left = standingSide()))
        extractor.reset()
        val right = extractor.extract(pose(right = standingSide()))

        assertEquals(PoseSide.LEFT, (left as PoseFeatureResult.Valid).sample.selectedSide)
        assertEquals(PoseSide.RIGHT, (right as PoseFeatureResult.Valid).sample.selectedSide)
    }

    @Test
    fun missingHipKneeOrAnkleIsRejected() {
        val missing = listOf(
            standingSide().copy(hip = null),
            standingSide().copy(knee = null),
            standingSide().copy(ankle = null),
        )

        missing.forEach { side ->
            val result = extractor.extract(pose(left = side))
            assertEquals(
                "lowerBodyLandmarkMissing",
                (result as PoseFeatureResult.Invalid).rejectReason,
            )
        }
    }

    @Test
    fun lowConfidenceIsRejectedWithoutLoweringTheThreshold() {
        val result =
            extractor.extract(
                pose(
                    left =
                        standingSide().copy(
                            ankle = point(50.0, 300.0, 0.40),
                        ),
                ),
            )

        assertEquals(
            PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE,
            (result as PoseFeatureResult.Invalid).warning,
        )
        assertEquals("lowerBodyConfidenceLow", result.rejectReason)
    }

    @Test
    fun legScaleIsNormalizedByFrameHeight() {
        val tooSmall =
            extractor.extract(
                pose(
                    left =
                        LowerBodySide(
                            hip = point(50.0, 100.0),
                            knee = point(50.0, 120.0),
                            ankle = point(50.0, 140.0),
                        ),
                ),
            )

        assertEquals(
            PoseQualityWarning.MOVE_CLOSER,
            (tooSmall as PoseFeatureResult.Invalid).warning,
        )
    }

    @Test
    fun strongerSideWinsAndSelectionIsStickyForShortConfidenceJitter() {
        val first =
            extractor.extract(
                pose(
                    timestampMs = 1_000,
                    left = standingSide(confidence = 0.90),
                    right = standingSide(confidence = 0.70),
                ),
            ) as PoseFeatureResult.Valid
        val sticky =
            extractor.extract(
                pose(
                    timestampMs = 1_300,
                    left = standingSide(confidence = 0.70),
                    right = standingSide(confidence = 0.95),
                ),
            ) as PoseFeatureResult.Valid
        val switched =
            extractor.extract(
                pose(
                    timestampMs = 1_600,
                    left = standingSide(confidence = 0.70),
                    right = standingSide(confidence = 0.95),
                ),
            ) as PoseFeatureResult.Valid

        assertEquals(PoseSide.LEFT, first.sample.selectedSide)
        assertEquals(PoseSide.LEFT, sticky.sample.selectedSide)
        assertEquals(PoseSide.RIGHT, switched.sample.selectedSide)
    }

    @Test
    fun noPoseAndPartialPoseExposeDiagnosticReasons() {
        val noPose = extractor.extract(pose(poseDetected = false))
        val partial = extractor.extract(pose(left = standingSide().copy(ankle = null)))

        assertEquals("poseNotDetected", (noPose as PoseFeatureResult.Invalid).rejectReason)
        assertEquals(
            "lowerBodyLandmarkMissing",
            (partial as PoseFeatureResult.Invalid).rejectReason,
        )
        assertNull(noPose.quality.selectedSide)
    }

    private fun pose(
        left: LowerBodySide? = null,
        right: LowerBodySide? = null,
        timestampMs: Long = 1_000,
        poseDetected: Boolean = true,
    ) = LowerBodyPose(
        timestampMs = timestampMs,
        imageWidth = 400,
        imageHeight = 400,
        poseDetected = poseDetected,
        left = left,
        right = right,
    )

    private fun standingSide(confidence: Double = 0.90) =
        LowerBodySide(
            hip = point(50.0, 100.0, confidence),
            knee = point(50.0, 200.0, confidence),
            ankle = point(50.0, 300.0, confidence),
        )

    private fun point(
        x: Double,
        y: Double,
        confidence: Double = 0.90,
    ) = PosePoint(x, y, confidence)
}
