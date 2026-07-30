package com.kren.michizure.pose

import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseLandmark

/**
 * ML Kit adapter boundary. No ML Kit type is allowed past this class.
 */
object MlKitPoseAdapter {
    fun convert(
        pose: Pose,
        timestampMs: Long,
        imageWidth: Int,
        imageHeight: Int,
        mirrorHorizontally: Boolean,
    ): LowerBodyPose {
        return LowerBodyPose(
            timestampMs = timestampMs,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            poseDetected = pose.allPoseLandmarks.isNotEmpty(),
            left =
                side(
                    pose,
                    PoseLandmark.LEFT_HIP,
                    PoseLandmark.LEFT_KNEE,
                    PoseLandmark.LEFT_ANKLE,
                    imageWidth,
                    mirrorHorizontally,
                ),
            right =
                side(
                    pose,
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
        hipType: Int,
        kneeType: Int,
        ankleType: Int,
        imageWidth: Int,
        mirror: Boolean,
    ): LowerBodySide {
        return LowerBodySide(
            hip = point(pose.getPoseLandmark(hipType), imageWidth, mirror),
            knee = point(pose.getPoseLandmark(kneeType), imageWidth, mirror),
            ankle = point(pose.getPoseLandmark(ankleType), imageWidth, mirror),
        )
    }

    private fun point(
        landmark: PoseLandmark?,
        imageWidth: Int,
        mirror: Boolean,
    ): PosePoint? {
        landmark ?: return null
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
