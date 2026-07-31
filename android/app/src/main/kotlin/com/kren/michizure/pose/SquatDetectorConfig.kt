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
    val calibrationStandingMinimumKneeDeg: Double = 155.0,
    val standingMaximumHipDropRatio: Double = 0.12,
    val standingKneeBaselineDeltaDeg: Double = 12.0,
    val standingKneeMinimumDeg: Double = 143.0,
    val standingKneeMaximumDeg: Double = 168.0,
    val standingConfirmationMs: Long = 225,
    val descendingKneeBaselineDeltaDeg: Double = 20.0,
    val descendingKneeMinimumDeg: Double = 135.0,
    val descendingKneeMaximumDeg: Double = 160.0,
    val descendingHipDropRatio: Double = 0.06,
    val descendingStableMs: Long = 100,
    val bottomKneeBaselineDeltaDeg: Double = 35.0,
    val bottomKneeMinimumDeg: Double = 125.0,
    val bottomKneeMaximumDeg: Double = 140.0,
    val bottomHipDropRatio: Double = 0.10,
    val deepBottomAngleMarginDeg: Double = 8.0,
    val deepBottomMinimumHipDropRatio: Double = 0.06,
    val bottomConfirmationMs: Long = 125,
    val tooDeepKneeDeg: Double = 55.0,
    val tooDeepHipDropRatio: Double = 0.20,
    val ascendingStableMs: Long = 100,
    val returnStandingKneeBaselineDeltaDeg: Double = 15.0,
    val returnStandingKneeMinimumDeg: Double = 140.0,
    val returnStandingKneeMaximumDeg: Double = 168.0,
    val returnStandingMaximumHipDropRatio: Double = 0.15,
    val returnStandingConfirmationMs: Long = 200,
    val minimumRepDurationMs: Long = 800,
    val maximumRepDurationMs: Long = 6_000,
    val refractoryMs: Long = 500,
    val oneEuroMinCutoff: Double = 1.0,
    val oneEuroBeta: Double = 0.02,
    val oneEuroDerivativeCutoff: Double = 1.0,
    val oneEuroLongGapMs: Long = 400,
    val nativeOverlayFps: Int = 10,
) {
    val diagnosticIntervalMs: Long
        get() = 1_000L / diagnosticUiFps

    fun thresholdsFor(standingKneeAngle: Double): SquatCalibrationThresholds =
        SquatCalibrationThresholds(
            standingEnterAngle =
                (standingKneeAngle - standingKneeBaselineDeltaDeg)
                    .coerceIn(standingKneeMinimumDeg, standingKneeMaximumDeg),
            descendingStartAngle =
                (standingKneeAngle - descendingKneeBaselineDeltaDeg)
                    .coerceIn(descendingKneeMinimumDeg, descendingKneeMaximumDeg),
            bottomAngle =
                (standingKneeAngle - bottomKneeBaselineDeltaDeg)
                    .coerceIn(bottomKneeMinimumDeg, bottomKneeMaximumDeg),
            returnStandingAngle =
                (standingKneeAngle - returnStandingKneeBaselineDeltaDeg)
                    .coerceIn(returnStandingKneeMinimumDeg, returnStandingKneeMaximumDeg),
        )

    companion object {
        const val VERSION = "mediapipe-lite-knee-angle-hip-drop-v6"
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}

data class SquatCalibrationThresholds(
    val standingEnterAngle: Double,
    val descendingStartAngle: Double,
    val bottomAngle: Double,
    val returnStandingAngle: Double,
)
