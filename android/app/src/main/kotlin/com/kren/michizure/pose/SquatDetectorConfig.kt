package com.kren.michizure.pose

data class SquatDetectorConfig(
    val minimumLandmarkConfidence: Double = 0.65,
    val minimumSubjectHeightRatio: Double = 0.30,
    val maximumSubjectHeightRatio: Double = 0.98,
    val sideStickinessMs: Long = 500,
    val maximumFrameGapMs: Long = 250,
    val invalidTrackingGraceMs: Long = 250,
    val calibrationStableMs: Long = 1_000,
    val calibrationMaximumHipDriftRatio: Double = 0.03,
    val standingKneeDeg: Double = 160.0,
    val standingHipDeg: Double = 150.0,
    val standingStableMs: Long = 250,
    val descendingKneeDeg: Double = 150.0,
    val minimumMovementVelocityDegPerSec: Double = 15.0,
    val bottomKneeDeg: Double = 105.0,
    val bottomHipDeg: Double = 120.0,
    val bottomHipDropRatio: Double = 0.15,
    val bottomStableMs: Long = 100,
    val bottomExitKneeDeg: Double = 115.0,
    val minimumRepDurationMs: Long = 800,
    val maximumRepDurationMs: Long = 6_000,
    val minimumDescendingMs: Long = 200,
    val minimumAscendingMs: Long = 200,
    val minimumRangeOfMotionDeg: Double = 50.0,
    val minimumValidFrameRatio: Double = 0.80,
    val refractoryMs: Long = 500,
    val medianWindowSize: Int = 5,
    val emaAlpha: Double = 0.35,
) {
    companion object {
        const val VERSION = "squat-v1"
    }
}
