package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaPipePoseAdapterTest {
    @Test
    fun leftAndRightLowerBodyMapFromNormalizedCoordinates() {
        val landmarks = blankLandmarks()
        landmarks[23] = landmark(0.25, 0.20, visibility = 0.9, presence = 0.8)
        landmarks[25] = landmark(0.25, 0.50)
        landmarks[27] = landmark(0.25, 0.80)
        landmarks[24] = landmark(0.75, 0.20)
        landmarks[26] = landmark(0.75, 0.50)
        landmarks[28] = landmark(0.75, 0.80)

        val pose = MediaPipePoseAdapter.convert(result(landmarks))

        assertTrue(pose.poseDetected)
        assertEquals(100.0, requireNotNull(pose.left?.hip).x, 0.001)
        assertEquals(80.0, requireNotNull(pose.left?.hip).y, 0.001)
        assertEquals(0.8, requireNotNull(pose.left?.hip).confidence, 0.001)
        assertEquals(300.0, requireNotNull(pose.right?.ankle).x, 0.001)
    }

    @Test
    fun noPoseLowerBodyMissingLowVisibilityAndNanRemainDistinct() {
        val noPose = MediaPipePoseAdapter.convert(result(null))
        assertFalse(noPose.poseDetected)

        val missing = MediaPipePoseAdapter.convert(result(blankLandmarks()))
        assertTrue(missing.poseDetected)
        assertNull(missing.left?.hip)

        val low = blankLandmarks()
        low[23] = landmark(0.2, 0.2, visibility = 0.3, presence = 0.9)
        low[25] = landmark(0.2, 0.5)
        low[27] = landmark(0.2, 0.8)
        val lowPose = MediaPipePoseAdapter.convert(result(low))
        assertEquals(0.3, requireNotNull(lowPose.left?.hip).confidence, 0.001)

        val invalid = blankLandmarks()
        invalid[23] = landmark(Double.NaN, 0.2)
        assertNull(MediaPipePoseAdapter.convert(result(invalid)).left?.hip)
    }

    @Test
    fun optionalWorldCoordinateDoesNotAffectImageSpaceBoundary() {
        val landmarks = blankLandmarks()
        landmarks[23] = landmark(0.4, 0.3, z = -0.2)
        val pose = MediaPipePoseAdapter.convert(result(landmarks))

        assertEquals(160.0, requireNotNull(pose.left?.hip).x, 0.001)
    }

    private fun result(landmarks: List<MediaPipeLandmarkSample>?) =
        MediaPipePoseResultSample(
            timestampMs = 1_000,
            imageWidth = 400,
            imageHeight = 400,
            landmarks = landmarks,
        )

    private fun blankLandmarks() =
        MutableList(33) { landmark(0.0, 0.0, visibility = null, presence = null) }

    private fun landmark(
        x: Double,
        y: Double,
        z: Double = 0.0,
        visibility: Double? = 0.9,
        presence: Double? = 0.9,
    ) = MediaPipeLandmarkSample(x, y, z, visibility, presence)
}
