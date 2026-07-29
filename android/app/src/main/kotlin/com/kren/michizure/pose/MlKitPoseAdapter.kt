package com.kren.michizure.pose

import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseLandmark

object MlKitPoseAdapter {
    fun convert(
        pose: Pose,
        timestampMs: Long,
        imageWidth: Int,
        imageHeight: Int,
        mirrorHorizontally: Boolean,
    ): PoseLandmarkFrame {
        return PoseLandmarkFrame(
            timestampMs = timestampMs,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            left =
                side(
                    pose,
                    PoseLandmark.LEFT_SHOULDER,
                    PoseLandmark.LEFT_HIP,
                    PoseLandmark.LEFT_KNEE,
                    PoseLandmark.LEFT_ANKLE,
                    imageWidth,
                    mirrorHorizontally,
                ),
            right =
                side(
                    pose,
                    PoseLandmark.RIGHT_SHOULDER,
                    PoseLandmark.RIGHT_HIP,
                    PoseLandmark.RIGHT_KNEE,
                    PoseLandmark.RIGHT_ANKLE,
                    imageWidth,
                    mirrorHorizontally,
                ),
        )
    }

    private fun side(
        pose: Pose,
        shoulderType: Int,
        hipType: Int,
        kneeType: Int,
        ankleType: Int,
        imageWidth: Int,
        mirror: Boolean,
    ): BodySideLandmarks? {
        val shoulder = pose.getPoseLandmark(shoulderType) ?: return null
        val hip = pose.getPoseLandmark(hipType) ?: return null
        val knee = pose.getPoseLandmark(kneeType) ?: return null
        val ankle = pose.getPoseLandmark(ankleType) ?: return null
        return BodySideLandmarks(
            shoulder = point(shoulder, imageWidth, mirror),
            hip = point(hip, imageWidth, mirror),
            knee = point(knee, imageWidth, mirror),
            ankle = point(ankle, imageWidth, mirror),
        )
    }

    private fun point(
        landmark: PoseLandmark,
        imageWidth: Int,
        mirror: Boolean,
    ): PosePoint {
        return PosePoint(
            x =
                PoseCoordinateNormalizer.x(
                    landmark.position.x.toDouble(),
                    imageWidth,
                    mirror,
                ),
            y = landmark.position.y.toDouble(),
            confidence = landmark.inFrameLikelihood.toDouble(),
        )
    }
}
