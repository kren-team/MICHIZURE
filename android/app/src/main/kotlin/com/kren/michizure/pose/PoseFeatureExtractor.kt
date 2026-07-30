package com.kren.michizure.pose

import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.min

class PoseFeatureExtractor(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    private var selectedSide: PoseSide? = null
    private var selectedAtMs: Long = Long.MIN_VALUE

    fun extract(pose: LowerBodyPose): PoseFeatureResult {
        val baseQuality = quality(pose, selectedSide = null)
        if (pose.imageWidth <= 0 || pose.imageHeight <= 0) {
            return invalid(
                pose,
                PoseQualityWarning.SHOW_LOWER_BODY,
                baseQuality,
                "invalidFrameSize",
            )
        }
        if (!pose.poseDetected) {
            return invalid(
                pose,
                PoseQualityWarning.SHOW_LOWER_BODY,
                baseQuality,
                "poseNotDetected",
            )
        }

        val left = pose.left?.let { measure(it, PoseSide.LEFT) }
        val right = pose.right?.let { measure(it, PoseSide.RIGHT) }
        if (left == null && right == null) {
            return invalid(
                pose,
                PoseQualityWarning.SHOW_LOWER_BODY,
                baseQuality,
                "lowerBodyLandmarkMissing",
            )
        }
        val validLeft =
            left?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        val validRight =
            right?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        if (validLeft == null && validRight == null) {
            return invalid(
                pose,
                PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE,
                baseQuality,
                "lowerBodyConfidenceLow",
            )
        }

        val selected = selectSide(validLeft, validRight, pose.timestampMs)
        val quality = quality(pose, selected.side)
        val legLengthRatio = selected.legLength / pose.imageHeight.toDouble()
        if (legLengthRatio < config.minimumLegLengthRatio) {
            return invalid(
                pose,
                PoseQualityWarning.MOVE_CLOSER,
                quality,
                "lowerBodyTooSmall",
            )
        }
        if (legLengthRatio > config.maximumLegLengthRatio) {
            return invalid(
                pose,
                PoseQualityWarning.MOVE_FARTHER_BACK,
                quality,
                "lowerBodyTooClose",
            )
        }

        return PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = pose.timestampMs,
                    kneeAngleDeg = selected.kneeAngle,
                    hipY = selected.hipY / pose.imageHeight,
                    legLength = legLengthRatio,
                    confidence = selected.confidence,
                    selectedSide = selected.side,
                ),
            quality = quality,
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
        val ankle = landmarks.ankle ?: return null
        if (!hip.isUsable() || !knee.isUsable() || !ankle.isUsable()) return null
        val confidence = min(hip.confidence, min(knee.confidence, ankle.confidence))
        val kneeAngle = angle(hip, knee, ankle) ?: return null
        val legLength = distance(hip, knee) + distance(knee, ankle)
        if (!kneeAngle.isFinite() || !legLength.isFinite() || legLength <= 1e-6) {
            return null
        }
        return SideMeasurement(
            kneeAngle = kneeAngle,
            hipY = hip.y,
            legLength = legLength,
            confidence = confidence,
            side = side,
        )
    }

    private fun quality(
        pose: LowerBodyPose,
        selectedSide: PoseSide?,
    ) = PoseQualityMetrics(
        poseDetected = pose.poseDetected,
        leftHipConfidence = pose.left?.hip?.confidence,
        leftKneeConfidence = pose.left?.knee?.confidence,
        leftAnkleConfidence = pose.left?.ankle?.confidence,
        rightHipConfidence = pose.right?.hip?.confidence,
        rightKneeConfidence = pose.right?.knee?.confidence,
        rightAnkleConfidence = pose.right?.ankle?.confidence,
        selectedSide = selectedSide,
    )

    private fun angle(a: PosePoint, b: PosePoint, c: PosePoint): Double? {
        val ux = a.x - b.x
        val uy = a.y - b.y
        val vx = c.x - b.x
        val vy = c.y - b.y
        val uLength = hypot(ux, uy)
        val vLength = hypot(vx, vy)
        if (uLength <= 1e-6 || vLength <= 1e-6) return null
        val cosine = ((ux * vx + uy * vy) / (uLength * vLength)).coerceIn(-1.0, 1.0)
        return Math.toDegrees(acos(cosine))
    }

    private fun distance(a: PosePoint, b: PosePoint): Double =
        hypot(a.x - b.x, a.y - b.y)

    private fun PosePoint.isUsable(): Boolean =
        x.isFinite() && y.isFinite() && confidence.isFinite()

    private fun invalid(
        pose: LowerBodyPose,
        warning: PoseQualityWarning,
        quality: PoseQualityMetrics,
        reason: String,
    ) = PoseFeatureResult.Invalid(
        timestampMs = pose.timestampMs,
        warning = warning,
        quality = quality,
        rejectReason = reason,
    )

    private data class SideMeasurement(
        val kneeAngle: Double,
        val hipY: Double,
        val legLength: Double,
        val confidence: Double,
        val side: PoseSide,
    )
}
