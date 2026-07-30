package com.kren.michizure.pose

data class SquatDetectorConfig(
    val targetGpuAnalysisFps: Int = 15,
    val targetCpuAnalysisFps: Int = 10,
    val diagnosticUiFps: Int = 5,
    val preferGpuDelegate: Boolean = true,
    val minPoseDetectionConfidence: Float = 0.50f,
    val minPosePresenceConfidence: Float = 0.50f,
    val minPoseTrackingConfidence: Float = 0.50f,
    val minimumLandmarkConfidence: Double = 0.65,
    val minimumLegLengthRatio: Double = 0.22,
    val maximumLegLengthRatio: Double = 1.50,
    val sideStickinessMs: Long = 500,
    val sideSwitchConfidenceMargin: Double = 0.10,
    val maximumFrameGapMs: Long = 250,
    val invalidTrackingGraceMs: Long = 250,
    val calibrationStableMs: Long = 1_000,
    val calibrationMaximumHipDriftRatio: Double = 0.03,
    val calibrationMaximumKneeDriftDeg: Double = 8.0,
    val standingKneeDeg: Double = 155.0,
    val standingKneeBaselineToleranceDeg: Double = 12.0,
    val standingStableMs: Long = 250,
    val descendingKneeDeg: Double = 150.0,
    val descendingKneeBaselineDeltaDeg: Double = 12.0,
    val minimumMovementVelocityDegPerSec: Double = 15.0,
    val minimumHipVelocityRatioPerSec: Double = 0.02,
    val bottomKneeDeg: Double = 108.0,
    val bottomHipDropRatio: Double = 0.12,
    val bottomStableMs: Long = 100,
    val bottomExitKneeDeg: Double = 118.0,
    val minimumRepDurationMs: Long = 800,
    val maximumRepDurationMs: Long = 6_000,
    val minimumDescendingMs: Long = 200,
    val minimumAscendingMs: Long = 200,
    val minimumRangeOfMotionDeg: Double = 45.0,
    val minimumValidFrameRatio: Double = 0.80,
    val refractoryMs: Long = 500,
    val oneEuroMinCutoff: Double = 1.0,
    val oneEuroBeta: Double = 0.02,
    val oneEuroDerivativeCutoff: Double = 1.0,
    val oneEuroLongGapMs: Long = 500,
) {
    val diagnosticIntervalMs: Long
        get() = 1_000L / diagnosticUiFps

    companion object {
        const val VERSION = "mediapipe-lite-lower-body-v3"
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}
