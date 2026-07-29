package com.kren.michizure.pose

data class PosePoint(
    val x: Double,
    val y: Double,
    val confidence: Double,
)

data class BodySideLandmarks(
    val shoulder: PosePoint,
    val hip: PosePoint,
    val knee: PosePoint,
    val ankle: PosePoint,
)

data class PoseLandmarkFrame(
    val timestampMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val left: BodySideLandmarks?,
    val right: BodySideLandmarks?,
)

enum class PoseSide {
    LEFT,
    RIGHT,
    BOTH,
}

enum class PoseQualityWarning(val wireValue: String) {
    SHOW_FULL_BODY("showFullBody"),
    MOVE_FARTHER_BACK("moveFartherBack"),
    MOVE_CLOSER("moveCloser"),
    LOW_LIGHT_OR_CONFIDENCE("lowLightOrConfidence"),
    HOLD_STILL_TO_CALIBRATE("holdStillToCalibrate"),
    CAMERA_UNAVAILABLE("cameraUnavailable"),
}

data class PoseFeatureSample(
    val timestampMs: Long,
    val kneeAngleDeg: Double,
    val hipAngleDeg: Double,
    val hipY: Double,
    val legLength: Double,
    val confidence: Double,
    val selectedSide: PoseSide,
)

sealed interface PoseFeatureResult {
    data class Valid(val sample: PoseFeatureSample) : PoseFeatureResult

    data class Invalid(
        val timestampMs: Long,
        val warning: PoseQualityWarning,
    ) : PoseFeatureResult
}

enum class SquatState(val wireValue: String) {
    CALIBRATING("calibrating"),
    STANDING("standing"),
    DESCENDING("descending"),
    BOTTOM("bottom"),
    ASCENDING("ascending"),
}

data class SquatDetectorUpdate(
    val state: SquatState,
    val qualityWarning: PoseQualityWarning?,
    val repCompleted: Boolean,
    val repSequence: Int,
)
