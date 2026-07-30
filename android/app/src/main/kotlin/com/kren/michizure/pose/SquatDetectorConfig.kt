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
    val sideStickinessMs: Long = 500,
    val sideSwitchConfidenceMargin: Double = 0.10,
    val maximumFrameGapMs: Long = 250,
    val invalidTrackingGraceMs: Long = 250,
    val calibrationStableMs: Long = 1_000,
    val minimumCalibrationGapRatio: Double = 0.12,
    val calibrationMaximumHipDriftRatio: Double = 0.03,
    val calibrationMaximumGapDriftRatio: Double = 0.10,
    val standingGapRatio: Double = 0.75,
    val standingMaximumHipDropRatio: Double = 0.15,
    val standingStableMs: Long = 250,
    val descendingGapRatio: Double = 0.68,
    val descendingHipDropRatio: Double = 0.10,
    val descendingStableMs: Long = 100,
    val bottomGapRatio: Double = 0.30,
    val bottomHipDropRatio: Double = 0.35,
    val bottomStableMs: Long = 100,
    val bottomExitGapRatio: Double = 0.42,
    val bottomExitHipDropRatio: Double = 0.30,
    val ascendingStableMs: Long = 100,
    val minimumRepDurationMs: Long = 800,
    val maximumRepDurationMs: Long = 6_000,
    val minimumDescendingMs: Long = 200,
    val minimumAscendingMs: Long = 200,
    val minimumGapCompressionRatio: Double = 0.65,
    val minimumHipDropRatio: Double = 0.35,
    val minimumValidFrameRatio: Double = 0.80,
    val refractoryMs: Long = 500,
    val oneEuroMinCutoff: Double = 1.0,
    val oneEuroBeta: Double = 0.02,
    val oneEuroDerivativeCutoff: Double = 1.0,
    val oneEuroLongGapMs: Long = 500,
    val nativeOverlayFps: Int = 10,
    val overlayBandToleranceRatio: Double = 0.035,
) {
    val diagnosticIntervalMs: Long
        get() = 1_000L / diagnosticUiFps

    companion object {
        const val VERSION = "mediapipe-lite-hip-knee-v4"
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}
