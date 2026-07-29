package com.kren.michizure.pose

import kotlin.math.acos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

class PoseFeatureExtractor(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    private var selectedSide: PoseSide? = null
    private var selectedAtMs: Long = Long.MIN_VALUE

    fun extract(frame: PoseLandmarkFrame): PoseFeatureResult {
        if (frame.imageWidth <= 0 || frame.imageHeight <= 0) {
            return invalid(frame, PoseQualityWarning.SHOW_FULL_BODY)
        }
        val left = frame.left?.let { measure(it, PoseSide.LEFT) }
        val right = frame.right?.let { measure(it, PoseSide.RIGHT) }
        val validLeft = left?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        val validRight = right?.takeIf { it.confidence >= config.minimumLandmarkConfidence }
        if (validLeft == null && validRight == null) {
            return invalid(frame, PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE)
        }

        val selected = selectSide(validLeft, validRight, frame.timestampMs)
        val subjectHeightRatio =
            selected.subjectHeight / frame.imageHeight.toDouble()
        if (subjectHeightRatio < config.minimumSubjectHeightRatio) {
            return invalid(frame, PoseQualityWarning.MOVE_CLOSER)
        }
        if (subjectHeightRatio > config.maximumSubjectHeightRatio) {
            return invalid(frame, PoseQualityWarning.MOVE_FARTHER_BACK)
        }

        return PoseFeatureResult.Valid(
            PoseFeatureSample(
                timestampMs = frame.timestampMs,
                kneeAngleDeg = selected.kneeAngle,
                hipAngleDeg = selected.hipAngle,
                hipY = selected.hipY / frame.imageHeight,
                legLength = selected.legLength / frame.imageHeight,
                confidence = selected.confidence,
                selectedSide = selected.side,
            ),
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
            if (selectedSide == PoseSide.LEFT &&
                timestampMs - selectedAtMs <= config.sideStickinessMs
            ) {
                return left
            }
            if (selectedSide == PoseSide.RIGHT &&
                timestampMs - selectedAtMs <= config.sideStickinessMs
            ) {
                return right
            }
            if (kotlin.math.abs(left.confidence - right.confidence) < 0.10) {
                selectedSide = PoseSide.BOTH
                selectedAtMs = timestampMs
                return SideMeasurement(
                    kneeAngle = (left.kneeAngle + right.kneeAngle) / 2,
                    hipAngle = (left.hipAngle + right.hipAngle) / 2,
                    hipY = (left.hipY + right.hipY) / 2,
                    legLength = (left.legLength + right.legLength) / 2,
                    subjectHeight = (left.subjectHeight + right.subjectHeight) / 2,
                    confidence = min(left.confidence, right.confidence),
                    side = PoseSide.BOTH,
                )
            }
            val stronger = if (left.confidence >= right.confidence) left else right
            selectedSide = stronger.side
            selectedAtMs = timestampMs
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
        landmarks: BodySideLandmarks,
        poseSide: PoseSide,
    ): SideMeasurement? {
        val confidence =
            min(
                min(landmarks.shoulder.confidence, landmarks.hip.confidence),
                min(landmarks.knee.confidence, landmarks.ankle.confidence),
            )
        val kneeAngle =
            angle(landmarks.hip, landmarks.knee, landmarks.ankle) ?: return null
        val hipAngle =
            angle(landmarks.shoulder, landmarks.hip, landmarks.knee) ?: return null
        val thigh = distance(landmarks.hip, landmarks.knee)
        val shin = distance(landmarks.knee, landmarks.ankle)
        val legLength = thigh + shin
        if (legLength <= 1e-6) return null
        val subjectHeight =
            max(landmarks.shoulder.y, landmarks.ankle.y) -
                min(landmarks.shoulder.y, landmarks.ankle.y)
        if (subjectHeight <= 1e-6) return null
        return SideMeasurement(
            kneeAngle = kneeAngle,
            hipAngle = hipAngle,
            hipY = landmarks.hip.y,
            legLength = legLength,
            subjectHeight = subjectHeight,
            confidence = confidence,
            side = poseSide,
        )
    }

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

    private fun invalid(
        frame: PoseLandmarkFrame,
        warning: PoseQualityWarning,
    ) = PoseFeatureResult.Invalid(frame.timestampMs, warning)

    private data class SideMeasurement(
        val kneeAngle: Double,
        val hipAngle: Double,
        val hipY: Double,
        val legLength: Double,
        val subjectHeight: Double,
        val confidence: Double,
        val side: PoseSide,
    )
}
