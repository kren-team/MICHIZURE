package com.kren.michizure.pose

data class SquatDetectorConfig(
    val targetGpuAnalysisFps: Int = 12,
    val targetCpuAnalysisFps: Int = 8,
    val targetEmulatorAnalysisFps: Int = 6,
    val diagnosticUiFps: Int = 4,
    val preferGpuDelegate: Boolean = true,
    val minPoseDetectionConfidence: Float = 0.50f,
    val minPosePresenceConfidence: Float = 0.50f,
    val minPoseTrackingConfidence: Float = 0.50f,
    val minimumLandmarkConfidence: Double = 0.65,
    val minimumLegLengthRatio: Double = 0.22,
    val maximumLegLengthRatio: Double = 1.50,
    val sideStickinessMs: Long = 500,
    val sideSwitchConfidenceMargin: Double = 0.10,
    val velocityResetGapMs: Long = 400,
    val poseLossResetMs: Long = 1_500,
    val calibrationObservationMs: Long = 2_000,
    val calibrationTimeoutMs: Long = 3_000,
    val calibrationMinimumSamples: Int = 6,
    val calibrationTargetSamples: Int = 8,
    val calibrationMaximumHipDriftRatio: Double = 0.03,
    val calibrationMaximumKneeDriftDeg: Double = 8.0,
    val standingKneeDeg: Double = 155.0,
    val standingMaximumHipDropRatio: Double = 0.12,
    val standingKneeBaselineToleranceDeg: Double = 12.0,
    val standingConfirmationMs: Long = 250,
    val descendingKneeDeg: Double = 150.0,
    val descendingKneeBaselineDeltaDeg: Double = 12.0,
    val descendingHipDropRatio: Double = 0.08,
    val descendingStableMs: Long = 100,
    val bottomKneeDeg: Double = 120.0,
    val bottomHipDropRatio: Double = 0.20,
    val bottomConfirmationMs: Long = 150,
    val tooDeepKneeDeg: Double = 55.0,
    val tooDeepHipDropRatio: Double = 0.20,
    val bottomExitKneeDeg: Double = 125.0,
    val bottomExitMaximumHipDropRatio: Double = 0.18,
    val ascendingStableMs: Long = 100,
    val returnStandingKneeDeg: Double = 150.0,
    val returnStandingMaximumHipDropRatio: Double = 0.15,
    val returnStandingConfirmationMs: Long = 200,
    val minimumRepDurationMs: Long = 800,
    val maximumRepDurationMs: Long = 6_000,
    val minimumDescendingMs: Long = 200,
    val minimumAscendingMs: Long = 200,
    val minimumRangeOfMotionDeg: Double = 50.0,
    val minimumRepHipDropRatio: Double = 0.18,
    val refractoryMs: Long = 500,
    val oneEuroMinCutoff: Double = 1.0,
    val oneEuroBeta: Double = 0.02,
    val oneEuroDerivativeCutoff: Double = 1.0,
    val oneEuroLongGapMs: Long = 400,
    val nativeOverlayFps: Int = 10,
) {
    val diagnosticIntervalMs: Long
        get() = 1_000L / diagnosticUiFps

    companion object {
        const val VERSION = "mediapipe-lite-knee-angle-hip-drop-v5"
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}
