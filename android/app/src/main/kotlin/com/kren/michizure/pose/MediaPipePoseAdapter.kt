package com.kren.michizure.pose

import kotlin.math.min

data class MediaPipeLandmarkSample(
    val x: Double,
    val y: Double,
    val z: Double,
    val visibility: Double?,
    val presence: Double?,
)

data class MediaPipePoseResultSample(
    val timestampMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val landmarks: List<MediaPipeLandmarkSample>?,
)

/**
 * MediaPipe boundary. The rest of the detector sees only [LowerBodyPose].
 *
 * Coordinates are converted back to image-scaled coordinates before angle
 * calculation, avoiding aspect-ratio distortion from using normalized x/y as
 * though they shared one unit scale.
 */
object MediaPipePoseAdapter {
    fun convert(result: MediaPipePoseResultSample): LowerBodyPose {
        val landmarks = result.landmarks
        if (landmarks == null) {
            return LowerBodyPose(
                timestampMs = result.timestampMs,
                imageWidth = result.imageWidth,
                imageHeight = result.imageHeight,
                poseDetected = false,
                left = null,
                right = null,
            )
        }
        return LowerBodyPose(
            timestampMs = result.timestampMs,
            imageWidth = result.imageWidth,
            imageHeight = result.imageHeight,
            poseDetected = true,
            left =
                LowerBodySide(
                    hip = point(landmarks, LEFT_HIP, result),
                    knee = point(landmarks, LEFT_KNEE, result),
                    ankle = point(landmarks, LEFT_ANKLE, result),
                ),
            right =
                LowerBodySide(
                    hip = point(landmarks, RIGHT_HIP, result),
                    knee = point(landmarks, RIGHT_KNEE, result),
                    ankle = point(landmarks, RIGHT_ANKLE, result),
                ),
        )
    }

    private fun point(
        landmarks: List<MediaPipeLandmarkSample>,
        index: Int,
        result: MediaPipePoseResultSample,
    ): PosePoint? {
        val landmark = landmarks.getOrNull(index) ?: return null
        val visibility = landmark.visibility ?: return null
        val presence = landmark.presence ?: return null
        if (!landmark.x.isFinite() ||
            !landmark.y.isFinite() ||
            !visibility.isFinite() ||
            !presence.isFinite()
        ) {
            return null
        }
        return PosePoint(
            x = landmark.x * result.imageWidth,
            y = landmark.y * result.imageHeight,
            confidence = min(visibility, presence).coerceIn(0.0, 1.0),
        )
    }

    private const val LEFT_HIP = 23
    private const val RIGHT_HIP = 24
    private const val LEFT_KNEE = 25
    private const val RIGHT_KNEE = 26
    private const val LEFT_ANKLE = 27
    private const val RIGHT_ANKLE = 28
}
