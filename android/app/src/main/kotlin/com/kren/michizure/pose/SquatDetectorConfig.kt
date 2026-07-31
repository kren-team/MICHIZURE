package com.kren.michizure.pose

data class SquatDetectorConfig(
    val requestedAnalysisWidth: Int = 320,
    val requestedAnalysisHeight: Int = 240,
    val targetGpuAnalysisFps: Int = 10,
    val targetCpuAnalysisFps: Int = 8,
    val targetEmulatorAnalysisFps: Int = 4,
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
    val poseLossResetMs: Long = 2_000,
    val calibrationObservationMs: Long = 2_000,
    val calibrationTimeoutMs: Long = 3_000,
    val calibrationMinimumSamples: Int = 6,
    val calibrationTargetSamples: Int = 8,
    val calibrationMaximumHipDriftRatio: Double = 0.03,
    val calibrationMaximumKneeDriftDeg: Double = 8.0,
    val calibrationStandingMinimumKneeDeg: Double = 155.0,
    val standingMaximumHipDropRatio: Double = 0.12,
    val standingKneeBaselineDeltaDeg: Double = 18.0,
    val standingKneeMinimumDeg: Double = 135.0,
    val standingKneeMaximumDeg: Double = 165.0,
    val standingRelaxedKneeBaselineDeltaDeg: Double = 25.0,
    val standingRelaxedKneeMinimumDeg: Double = 130.0,
    val standingRelaxedKneeMaximumDeg: Double = 158.0,
    val descendingKneeBaselineDeltaDeg: Double = 20.0,
    val descendingKneeMinimumDeg: Double = 135.0,
    val descendingKneeMaximumDeg: Double = 160.0,
    val descendingHipDropRatio: Double = 0.06,
    val kneeOnlyBendDeltaDeg: Double = 28.0,
    val kneeAndHipBendDeltaDeg: Double = 20.0,
    val hipReversalMinimumKneeBendDeltaDeg: Double = 10.0,
    val bottomKneeBaselineDeltaDeg: Double = 28.0,
    val bottomKneeMinimumDeg: Double = 130.0,
    val bottomKneeMaximumDeg: Double = 145.0,
    val mediumHipDropRatio: Double = 0.06,
    val strongHipDropRatio: Double = 0.10,
    val kneeStrongEvidenceScore: Int = 3,
    val kneeMediumEvidenceScore: Int = 2,
    val kneeMinimumEvidenceScore: Int = 1,
    val hipStrongEvidenceScore: Int = 3,
    val hipMediumEvidenceScore: Int = 2,
    val reversalEvidenceScore: Int = 2,
    val bottomEvidenceRequiredScore: Int = 3,
    val movementKneeDeltaDeg: Double = 3.0,
    val movementHipDropDeltaRatio: Double = 0.015,
    val initialDownwardKneeDeltaDeg: Double = 5.0,
    val initialDownwardHipDropRatio: Double = 0.03,
    val tooDeepKneeDeg: Double = 55.0,
    val tooDeepHipDropRatio: Double = 0.20,
    val returnStandingKneeBaselineDeltaDeg: Double = 22.0,
    val returnStandingKneeMinimumDeg: Double = 133.0,
    val returnStandingKneeMaximumDeg: Double = 160.0,
    val returnStandingRelaxedKneeBaselineDeltaDeg: Double = 28.0,
    val returnStandingRelaxedKneeMinimumDeg: Double = 127.0,
    val returnStandingRelaxedKneeMaximumDeg: Double = 153.0,
    val returnStandingMaximumHipDropRatio: Double = 0.15,
    val returnStandingConfirmationMs: Long = 150,
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
            standingRelaxedAngle =
                (standingKneeAngle - standingRelaxedKneeBaselineDeltaDeg)
                    .coerceIn(standingRelaxedKneeMinimumDeg, standingRelaxedKneeMaximumDeg),
            descendingStartAngle =
                (standingKneeAngle - descendingKneeBaselineDeltaDeg)
                    .coerceIn(descendingKneeMinimumDeg, descendingKneeMaximumDeg),
            bottomAngle =
                (standingKneeAngle - bottomKneeBaselineDeltaDeg)
                    .coerceIn(bottomKneeMinimumDeg, bottomKneeMaximumDeg),
            returnStandingAngle =
                (standingKneeAngle - returnStandingKneeBaselineDeltaDeg)
                    .coerceIn(returnStandingKneeMinimumDeg, returnStandingKneeMaximumDeg),
            returnStandingRelaxedAngle =
                (standingKneeAngle - returnStandingRelaxedKneeBaselineDeltaDeg)
                    .coerceIn(
                        returnStandingRelaxedKneeMinimumDeg,
                        returnStandingRelaxedKneeMaximumDeg,
                    ),
        )

    fun bottomEvidence(
        calibratedStandingAngle: Double,
        minimumKneeAngle: Double,
        maximumHipDrop: Double,
        downwardMovementObserved: Boolean,
        upwardMovementObserved: Boolean,
    ): BottomEvidence {
        val kneeBendDelta = (calibratedStandingAngle - minimumKneeAngle).coerceAtLeast(0.0)
        val bottomAngle = thresholdsFor(calibratedStandingAngle).bottomAngle
        val kneeOnlyReached =
            kneeBendDelta >= kneeOnlyBendDeltaDeg || minimumKneeAngle <= bottomAngle
        val kneeScore =
            when {
                kneeOnlyReached -> kneeStrongEvidenceScore
                kneeBendDelta >= kneeAndHipBendDeltaDeg -> kneeMediumEvidenceScore
                kneeBendDelta >= hipReversalMinimumKneeBendDeltaDeg -> kneeMinimumEvidenceScore
                else -> 0
            }
        val hipScore =
            when {
                maximumHipDrop >= strongHipDropRatio -> hipStrongEvidenceScore
                maximumHipDrop >= mediumHipDropRatio -> hipMediumEvidenceScore
                else -> 0
            }
        val reversalScore =
            if (downwardMovementObserved && upwardMovementObserved) {
                reversalEvidenceScore
            } else {
                0
            }
        val score = kneeScore + hipScore + reversalScore
        val hasActualChange =
            kneeBendDelta >= hipReversalMinimumKneeBendDeltaDeg ||
                maximumHipDrop >= mediumHipDropRatio
        val path =
            when {
                score < bottomEvidenceRequiredScore || !hasActualChange -> null
                kneeOnlyReached -> BottomEvidencePath.KNEE_ONLY
                kneeBendDelta >= kneeAndHipBendDeltaDeg &&
                    maximumHipDrop >= mediumHipDropRatio -> BottomEvidencePath.KNEE_AND_HIP
                maximumHipDrop >= strongHipDropRatio &&
                    downwardMovementObserved &&
                    upwardMovementObserved &&
                    kneeBendDelta >= hipReversalMinimumKneeBendDeltaDeg ->
                    BottomEvidencePath.HIP_AND_REVERSAL
                else -> null
            }
        return BottomEvidence(
            score = score,
            path = path,
            kneeBendDeltaDeg = kneeBendDelta,
        )
    }

    companion object {
        const val VERSION = "mediapipe-lite-multi-evidence-v7"
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}

data class SquatCalibrationThresholds(
    val standingEnterAngle: Double,
    val standingRelaxedAngle: Double,
    val descendingStartAngle: Double,
    val bottomAngle: Double,
    val returnStandingAngle: Double,
    val returnStandingRelaxedAngle: Double,
)

enum class BottomEvidencePath(val wireValue: String, val transitionReason: String) {
    KNEE_ONLY("KNEE_ONLY", "BOTTOM_BY_KNEE"),
    KNEE_AND_HIP("KNEE_AND_HIP", "BOTTOM_BY_KNEE_AND_HIP"),
    HIP_AND_REVERSAL("HIP_AND_REVERSAL", "BOTTOM_BY_HIP_REVERSAL"),
}

data class BottomEvidence(
    val score: Int,
    val path: BottomEvidencePath?,
    val kneeBendDeltaDeg: Double,
)
