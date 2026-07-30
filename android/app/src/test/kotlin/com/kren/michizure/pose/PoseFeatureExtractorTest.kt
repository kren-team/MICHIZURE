package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PoseFeatureExtractorTest {
    private val extractor = PoseFeatureExtractor()

    @Test
    fun hipAndKneeOnlyPassWithoutFaceShoulderOrAnkle() {
        val result = extractor.extract(pose(left = standingSide(ankle = null)))

        assertTrue(result is PoseFeatureResult.Valid)
        val sample = (result as PoseFeatureResult.Valid).sample
        assertEquals(0.25, sample.hipY, 0.001)
        assertEquals(0.50, sample.kneeY, 0.001)
        assertEquals(PoseSide.LEFT, sample.selectedSide)
        assertEquals(PoseTrackingStatus.VALID, result.quality.trackingStatus)
    }

    @Test
    fun eitherLeftOrRightSameSideHipKneeCanPass() {
        val left = extractor.extract(pose(left = standingSide()))
        extractor.reset()
        val right = extractor.extract(pose(right = standingSide()))

        assertEquals(PoseSide.LEFT, (left as PoseFeatureResult.Valid).sample.selectedSide)
        assertEquals(PoseSide.RIGHT, (right as PoseFeatureResult.Valid).sample.selectedSide)
    }

    @Test
    fun missingHipAndMissingKneeAreDistinct() {
        val missingHip =
            extractor.extract(pose(left = standingSide().copy(hip = null)))
                as PoseFeatureResult.Invalid
        val missingKnee =
            extractor.extract(pose(left = standingSide().copy(knee = null)))
                as PoseFeatureResult.Invalid

        assertEquals(PoseTrackingStatus.HIP_UNAVAILABLE, missingHip.quality.trackingStatus)
        assertEquals(PoseQualityWarning.HIP_UNAVAILABLE, missingHip.warning)
        assertEquals("hipUnavailable", missingHip.rejectReason)
        assertEquals(PoseTrackingStatus.KNEE_UNAVAILABLE, missingKnee.quality.trackingStatus)
        assertEquals(PoseQualityWarning.KNEE_UNAVAILABLE, missingKnee.warning)
        assertEquals("kneeUnavailable", missingKnee.rejectReason)
    }

    @Test
    fun lowHipOrKneeConfidenceIsRejectedWithoutRequiringAnkle() {
        val result =
            extractor.extract(
                pose(
                    left =
                        standingSide(ankle = null).copy(
                            knee = point(50.0, 200.0, 0.40),
                        ),
                ),
            ) as PoseFeatureResult.Invalid

        assertEquals(PoseTrackingStatus.CONFIDENCE_INSUFFICIENT, result.quality.trackingStatus)
        assertEquals(PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE, result.warning)
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
    fun noPoseIsNotMisreportedAsLowConfidence() {
        val noPose = extractor.extract(pose(poseDetected = false))
            as PoseFeatureResult.Invalid

        assertEquals(PoseTrackingStatus.NO_POSE, noPose.quality.trackingStatus)
        assertEquals(PoseQualityWarning.NO_POSE_DETECTED, noPose.warning)
        assertEquals("poseNotDetected", noPose.rejectReason)
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

    private fun standingSide(
        confidence: Double = 0.90,
        ankle: PosePoint? = point(50.0, 300.0, confidence),
    ) = LowerBodySide(
        hip = point(50.0, 100.0, confidence),
        knee = point(50.0, 200.0, confidence),
        ankle = ankle,
    )

    private fun point(
        x: Double,
        y: Double,
        confidence: Double = 0.90,
    ) = PosePoint(x, y, confidence)
}
