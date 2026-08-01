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
            Triple(
                standingSide().copy(hip = null),
                "hipUnavailable",
                PoseTrackingStatus.HIP_UNAVAILABLE,
            ),
            Triple(
                standingSide().copy(knee = null),
                "kneeUnavailable",
                PoseTrackingStatus.KNEE_UNAVAILABLE,
            ),
            Triple(
                standingSide().copy(ankle = null),
                "ankleUnavailable",
                PoseTrackingStatus.ANKLE_UNAVAILABLE,
            ),
        )

        missing.forEach { (side, reason, trackingStatus) ->
            val result = extractor.extract(pose(left = side))
            assertEquals(
                reason,
                (result as PoseFeatureResult.Invalid).rejectReason,
            )
            assertEquals(trackingStatus, result.quality.trackingStatus)
        }
    }

    @Test
    fun lowConfidenceStandingGeometryUsesCalibrationOnlyFallback() {
        val result =
            extractor.extract(
                pose(
                    left =
                        standingSide().copy(
                            ankle = point(50.0, 300.0, 0.40),
                        ),
                ),
            )

        val candidate = result as PoseFeatureResult.CalibrationCandidate
        assertEquals(PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE, candidate.warning)
        assertEquals(CalibrationQualityPath.ANGLE_CONFIDENCE_FALLBACK, candidate.qualityPath)
        assertEquals("lowerBodyConfidenceLow", result.rejectReason)
    }

    @Test
    fun tooSmallStandingGeometryUsesCalibrationOnlyFallback() {
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

        val candidate = tooSmall as PoseFeatureResult.CalibrationCandidate
        assertEquals(PoseQualityWarning.MOVE_CLOSER, candidate.warning)
        assertEquals(CalibrationQualityPath.ANGLE_SIZE_FALLBACK, candidate.qualityPath)
    }

    @Test
    fun confidenceFallbackStillRequiresTwoRelaxedLandmarksAndInBoundsGeometry() {
        val tooWeak =
            extractor.extract(
                pose(
                    left =
                        standingSide().copy(
                            hip = point(50.0, 100.0, 0.10),
                            knee = point(50.0, 200.0, 0.10),
                            ankle = point(50.0, 300.0, 0.90),
                        ),
                ),
            )
        extractor.reset()
        val outside =
            extractor.extract(
                pose(
                    left =
                        LowerBodySide(
                            hip = point(-200.0, 100.0, 0.90),
                            knee = point(-200.0, 200.0, 0.90),
                            ankle = point(-200.0, 300.0, 0.40),
                        ),
                ),
            )

        assertEquals("lowerBodyConfidenceLow", (tooWeak as PoseFeatureResult.Invalid).rejectReason)
        assertEquals("lowerBodyConfidenceLow", (outside as PoseFeatureResult.Invalid).rejectReason)
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
            "ankleUnavailable",
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
