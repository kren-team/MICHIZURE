package com.kren.michizure.pose

import kotlin.math.min

/**
 * Reduces a MediaPipe-independent pose to same-side hip/knee vertical data.
 *
 * Ankle, shoulder, face, joint angles and velocity are intentionally not part
 * of the production quality gate. They made the real-camera framing brittle
 * without adding evidence that the MVP detector needed them.
 */
class PoseFeatureExtractor(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    private var selectedSide: PoseSide? = null
    private var selectedAtMs: Long = Long.MIN_VALUE

    fun extract(pose: LowerBodyPose): PoseFeatureResult {
        if (pose.imageWidth <= 0 || pose.imageHeight <= 0) {
            return invalid(
                pose,
                PoseQualityWarning.NO_POSE_DETECTED,
                PoseTrackingStatus.NO_POSE,
                "invalidFrameSize",
            )
        }
        if (!pose.poseDetected) {
            return invalid(
                pose,
                PoseQualityWarning.NO_POSE_DETECTED,
                PoseTrackingStatus.NO_POSE,
                "poseNotDetected",
            )
        }

        val left = pose.left?.let { measure(it, PoseSide.LEFT) }
        val right = pose.right?.let { measure(it, PoseSide.RIGHT) }
        val completeSides = listOfNotNull(left, right)
        if (completeSides.isEmpty()) {
            val hasHip = pose.left?.hip?.isUsable() == true || pose.right?.hip?.isUsable() == true
            return if (!hasHip) {
                invalid(
                    pose,
                    PoseQualityWarning.HIP_UNAVAILABLE,
                    PoseTrackingStatus.HIP_UNAVAILABLE,
                    "hipUnavailable",
                )
            } else {
                invalid(
                    pose,
                    PoseQualityWarning.KNEE_UNAVAILABLE,
                    PoseTrackingStatus.KNEE_UNAVAILABLE,
                    "kneeUnavailable",
                )
            }
        }

        val validLeft =
            left?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        val validRight =
            right?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        if (validLeft == null && validRight == null) {
            return invalid(
                pose,
                PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE,
                PoseTrackingStatus.CONFIDENCE_INSUFFICIENT,
                "hipKneeConfidenceLow",
            )
        }

        val selected = selectSide(validLeft, validRight, pose.timestampMs)
        return PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = pose.timestampMs,
                    hipY = selected.hipY / pose.imageHeight,
                    kneeY = selected.kneeY / pose.imageHeight,
                    confidence = selected.confidence,
                    selectedSide = selected.side,
                ),
            quality = quality(pose, PoseTrackingStatus.VALID, selected.side),
        )
    }

    fun reset() {
        selectedSide = null
        selectedAtMs = Long.MIN_VALUE
    }

    private fun selectSide(
        left: SideMeasurement?,
        right: SideMeasurement?,
        timestampMs: Long,
    ): SideMeasurement {
        if (left != null && right != null) {
            val sticky =
                when (selectedSide) {
                    PoseSide.LEFT -> left
                    PoseSide.RIGHT -> right
                    null -> null
                }
            if (sticky != null &&
                timestampMs - selectedAtMs <= config.sideStickinessMs
            ) {
                return sticky
            }
            val stronger =
                when {
                    left.confidence >= right.confidence +
                        config.sideSwitchConfidenceMargin -> left
                    right.confidence >= left.confidence +
                        config.sideSwitchConfidenceMargin -> right
                    selectedSide == PoseSide.RIGHT -> right
                    else -> left
                }
            if (selectedSide != stronger.side) {
                selectedSide = stronger.side
                selectedAtMs = timestampMs
            }
            return stronger
        }
        val only = left ?: requireNotNull(right)
        if (selectedSide != only.side) {
            selectedSide = only.side
            selectedAtMs = timestampMs
        }
        return only
    }

    private fun measure(
        landmarks: LowerBodySide,
        side: PoseSide,
    ): SideMeasurement? {
        val hip = landmarks.hip ?: return null
        val knee = landmarks.knee ?: return null
        if (!hip.isUsable() || !knee.isUsable()) return null
        return SideMeasurement(
            hipY = hip.y,
            kneeY = knee.y,
            confidence = min(hip.confidence, knee.confidence),
            side = side,
        )
    }

    private fun quality(
        pose: LowerBodyPose,
        trackingStatus: PoseTrackingStatus,
        selectedSide: PoseSide?,
    ) = PoseQualityMetrics(
        poseDetected = pose.poseDetected,
        trackingStatus = trackingStatus,
        leftHipConfidence = pose.left?.hip?.confidence,
        leftKneeConfidence = pose.left?.knee?.confidence,
        leftAnkleConfidence = pose.left?.ankle?.confidence,
        rightHipConfidence = pose.right?.hip?.confidence,
        rightKneeConfidence = pose.right?.knee?.confidence,
        rightAnkleConfidence = pose.right?.ankle?.confidence,
        selectedSide = selectedSide,
    )

    private fun invalid(
        pose: LowerBodyPose,
        warning: PoseQualityWarning,
        trackingStatus: PoseTrackingStatus,
        reason: String,
    ) = PoseFeatureResult.Invalid(
        timestampMs = pose.timestampMs,
        warning = warning,
        quality = quality(pose, trackingStatus, selectedSide = null),
        rejectReason = reason,
    )

    private fun PosePoint.isUsable(): Boolean =
        x.isFinite() && y.isFinite() && confidence.isFinite()

    private data class SideMeasurement(
        val hipY: Double,
        val kneeY: Double,
        val confidence: Double,
        val side: PoseSide,
    )
}
