package com.kren.michizure.pose

data class PosePoint(
    val x: Double,
    val y: Double,
    val confidence: Double,
)

/**
 * Model-independent lower-body pose. Camera and pose SDK adapters must reduce
 * their output to this type before feature extraction.
 */
data class LowerBodySide(
    val hip: PosePoint?,
    val knee: PosePoint?,
    val ankle: PosePoint?,
)

data class LowerBodyPose(
    val timestampMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val poseDetected: Boolean,
    val left: LowerBodySide?,
    val right: LowerBodySide?,
)

enum class PoseSide(val wireValue: String) {
    LEFT("left"),
    RIGHT("right"),
}

enum class PoseQualityWarning(val wireValue: String) {
    NO_POSE_DETECTED("noPoseDetected"),
    HIP_UNAVAILABLE("hipUnavailable"),
    KNEE_UNAVAILABLE("kneeUnavailable"),
    ANKLE_UNAVAILABLE("ankleUnavailable"),
    MOVE_FARTHER_BACK("moveFartherBack"),
    MOVE_CLOSER("moveCloser"),
    LOW_LIGHT_OR_CONFIDENCE("lowLightOrConfidence"),
    HOLD_STILL_TO_CALIBRATE("holdStillToCalibrate"),
    SQUAT_DEEPER("squatDeeper"),
    TOO_DEEP("tooDeep"),
    CAMERA_UNAVAILABLE("cameraUnavailable"),
}

enum class PoseTrackingStatus(val wireValue: String) {
    NO_POSE("noPose"),
    HIP_UNAVAILABLE("hipUnavailable"),
    KNEE_UNAVAILABLE("kneeUnavailable"),
    ANKLE_UNAVAILABLE("ankleUnavailable"),
    CONFIDENCE_INSUFFICIENT("confidenceInsufficient"),
    VALID("valid"),
}

data class PoseQualityMetrics(
    val poseDetected: Boolean,
    val leftHipConfidence: Double?,
    val leftKneeConfidence: Double?,
    val leftAnkleConfidence: Double?,
    val rightHipConfidence: Double?,
    val rightKneeConfidence: Double?,
    val rightAnkleConfidence: Double?,
    val selectedSide: PoseSide?,
    val trackingStatus: PoseTrackingStatus = PoseTrackingStatus.NO_POSE,
) {
    companion object {
        val EMPTY =
            PoseQualityMetrics(
                poseDetected = false,
                leftHipConfidence = null,
                leftKneeConfidence = null,
                leftAnkleConfidence = null,
                rightHipConfidence = null,
                rightKneeConfidence = null,
                rightAnkleConfidence = null,
                selectedSide = null,
                trackingStatus = PoseTrackingStatus.NO_POSE,
            )
    }
}

data class PoseFeatureSample(
    val timestampMs: Long,
    val kneeAngleDeg: Double,
    val rawKneeAngleDeg: Double = kneeAngleDeg,
    val hipY: Double,
    val legLength: Double,
    val confidence: Double,
    val selectedSide: PoseSide,
)

sealed interface PoseFeatureResult {
    val timestampMs: Long
    val quality: PoseQualityMetrics

    data class Valid(
        val sample: PoseFeatureSample,
        override val quality: PoseQualityMetrics = PoseQualityMetrics.EMPTY,
    ) : PoseFeatureResult {
        override val timestampMs: Long
            get() = sample.timestampMs
    }

    data class Invalid(
        override val timestampMs: Long,
        val warning: PoseQualityWarning,
        override val quality: PoseQualityMetrics = PoseQualityMetrics.EMPTY,
        val rejectReason: String = "qualityGate",
    ) : PoseFeatureResult
}

enum class SquatState(val wireValue: String) {
    CALIBRATING("calibrating"),
    STANDING("standing"),
    DESCENDING("descending"),
    BOTTOM("bottom"),
    ASCENDING("ascending"),
}

data class SquatFrameDiagnostics(
    val poseDetected: Boolean,
    val selectedSide: PoseSide?,
    val leftHipConfidence: Double?,
    val leftKneeConfidence: Double?,
    val leftAnkleConfidence: Double?,
    val rightHipConfidence: Double?,
    val rightKneeConfidence: Double?,
    val rightAnkleConfidence: Double?,
    val kneeAngleDeg: Double?,
    val rawKneeAngleDeg: Double?,
    val normalizedHipDrop: Double?,
    val kneeAngularVelocity: Double?,
    val hipVerticalVelocity: Double?,
    val latestRejectReason: String?,
    val rejectedAttempts: Int,
    val trackingStatus: PoseTrackingStatus,
    val previousState: SquatState?,
    val lastTransitionReason: String?,
    val lastResetReason: String?,
    val frameDtMs: Long?,
    val validPoseAgeMs: Long?,
    val effectiveValidPoseFps: Double,
    val calibrationSampleCount: Int,
    val calibrationStatus: String,
    val bottomReached: Boolean,
    val standingConfirmationDurationMs: Long,
    val bottomConfirmationDurationMs: Long,
    val returnStandingDurationMs: Long,
    val currentRepDurationMs: Long?,
    val calibratedStandingKneeAngleDeg: Double?,
    val standingThresholdDeg: Double,
    val descendingThresholdDeg: Double,
    val bottomThresholdDeg: Double,
    val returnStandingThresholdDeg: Double,
    val minimumAttemptKneeAngleDeg: Double?,
    val maximumAttemptHipDropRatio: Double?,
    val kneeBendDeltaDeg: Double?,
    val downwardMovementObserved: Boolean,
    val upwardMovementObserved: Boolean,
    val bottomEvidenceScore: Int,
    val bottomEvidencePath: BottomEvidencePath?,
    val attemptStartTimestampMs: Long?,
    val lastValidPoseTimestampMs: Long?,
    val baselineHipY: Double?,
    val legScale: Double?,
    val baselineJitter: Double?,
    val calibrationSelectedSide: PoseSide?,
)

data class SquatDetectorUpdate(
    val state: SquatState,
    val qualityWarning: PoseQualityWarning?,
    val repCompleted: Boolean,
    val repSequence: Int,
    val diagnostics: SquatFrameDiagnostics,
)
