package com.kren.michizure.pose

data class SquatDetectorConfig(
    val requestedAnalysisWidth: Int = 320,
    val requestedAnalysisHeight: Int = 240,
    val targetGpuAnalysisFps: Int = 10,
    val targetCpuAnalysisFps: Int = 8,
    val targetEmulatorAnalysisFps: Int = 4,
    val hostReconnectIntervalMs: Long = 1_000,
    val diagnosticUiFps: Int = 1,
    val preferGpuDelegate: Boolean = true,
    val minPoseDetectionConfidence: Float = 0.50f,
    val minPosePresenceConfidence: Float = 0.50f,
    val minPoseTrackingConfidence: Float = 0.50f,
    val minimumLandmarkConfidence: Double = 0.65,
    val calibrationFallbackConfidence: Double = 0.22,
    val calibrationCoordinateMarginRatio: Double = 0.25,
    val minimumLegLengthRatio: Double = 0.22,
    val maximumLegLengthRatio: Double = 1.50,
    val sideStickinessMs: Long = 500,
    val sideSwitchConfidenceMargin: Double = 0.10,
    val sideMissingGraceMs: Long = 2_000,
    val sideChangeConfirmationSamples: Int = 2,
    val velocityResetGapMs: Long = 400,
    val emulatorPoseLossResetMs: Long = 4_000,
    val physicalPoseLossResetMs: Long = 2_000,
    val emulatorReturnPoseWaitMs: Long = 3_000,
    val physicalReturnPoseWaitMs: Long = 3_000,
    val calibrationWindowMs: Long = 8_000,
    val emulatorCalibrationTimeoutMs: Long = 12_000,
    val physicalCalibrationTimeoutMs: Long = 8_000,
    val calibrationMinimumSamples: Int = 2,
    val calibrationPreferredSamples: Int = 3,
    val calibrationTargetSamples: Int = 8,
    val calibrationMaximumHipDriftRatio: Double = 0.12,
    val calibrationMaximumKneeDriftDeg: Double = 8.0,
    val calibrationAuxiliaryStandingMinimumKneeDeg: Double = 150.0,
    val calibrationStrongStandingMinimumKneeDeg: Double = 160.0,
    val calibrationProvisionalStandingMinimumKneeDeg: Double = 165.0,
    val calibrationMaximumAngleRangeDeg: Double = 20.0,
    val calibrationAutoDescentDeltaDeg: Double = 20.0,
    val standingMaximumHipDropRatio: Double = 0.12,
    val standingKneeBaselineDeltaDeg: Double = 25.0,
    val standingKneeMinimumDeg: Double = 135.0,
    val standingKneeMaximumDeg: Double = 165.0,
    val standingRelaxedKneeBaselineDeltaDeg: Double = 32.0,
    val standingRelaxedKneeMinimumDeg: Double = 130.0,
    val standingRelaxedKneeMaximumDeg: Double = 158.0,
    val descendingKneeBaselineDeltaDeg: Double = 20.0,
    val descendingKneeMinimumDeg: Double = 135.0,
    val descendingKneeMaximumDeg: Double = 160.0,
    val descendingHipDropRatio: Double = 0.06,
    val kneeOnlyBendDeltaDeg: Double = 22.0,
    val kneeAndHipBendDeltaDeg: Double = 14.0,
    val hipReversalMinimumKneeBendDeltaDeg: Double = 8.0,
    val bottomKneeBaselineDeltaDeg: Double = 24.0,
    val bottomKneeMinimumDeg: Double = 135.0,
    val bottomKneeMaximumDeg: Double = 150.0,
    val mediumHipDropRatio: Double = 0.04,
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
    val directionWindowSamples: Int = 3,
    val minimumKneeTrendDegrees: Double = 4.0,
    val minimumHipTrend: Double = 0.025,
    val bottomAscentKneeRecoveryDeg: Double = 8.0,
    val bottomAscentHipRecoveryRatio: Double = 0.08,
    val bottomReentryKneeDeltaDeg: Double = 8.0,
    val initialDownwardKneeDeltaDeg: Double = 5.0,
    val initialDownwardHipDropRatio: Double = 0.03,
    val tooDeepKneeDeg: Double = 55.0,
    val tooDeepHipDropRatio: Double = 0.20,
    val returnStandingKneeBaselineDeltaDeg: Double = 25.0,
    val returnStandingKneeMinimumDeg: Double = 130.0,
    val returnStandingKneeMaximumDeg: Double = 155.0,
    val returnStandingRelaxedKneeBaselineDeltaDeg: Double = 35.0,
    val returnStandingRelaxedKneeMinimumDeg: Double = 125.0,
    val returnStandingRelaxedKneeMaximumDeg: Double = 150.0,
    val returnStandingMaximumHipDropRatio: Double = 0.15,
    val returnStandingAbsoluteKneeDeg: Double = 145.0,
    val returnStandingMinimumRecoveryDeg: Double = 30.0,
    val returnStandingAbsoluteMinimumRecoveryDeg: Double = 35.0,
    val returnStandingHipAssistedKneeDeg: Double = 140.0,
    val returnStandingHipAssistedMinimumRecoveryDeg: Double = 30.0,
    val returnStandingMinimumHipRecoveryRatio: Double = 0.50,
    val minimumAcceptedKneeBendDeltaDeg: Double = 20.0,
    val returnStandingConfirmationMs: Long = 100,
    val minimumRepDurationMs: Long = 400,
    val maximumRepDurationMs: Long = 12_000,
    val refractoryMs: Long = 500,
    val oneEuroMinCutoff: Double = 1.0,
    val oneEuroBeta: Double = 0.02,
    val oneEuroDerivativeCutoff: Double = 1.0,
    val oneEuroLongGapMs: Long = 400,
    val nativeOverlayFps: Int = 10,
    val debugTraceFps: Int = 5,
) {
    val diagnosticIntervalMs: Long
        get() = 1_000L / diagnosticUiFps

    fun poseLossResetMs(isEmulator: Boolean): Long =
        if (isEmulator) emulatorPoseLossResetMs else physicalPoseLossResetMs

    fun returnPoseWaitMs(isEmulator: Boolean): Long =
        if (isEmulator) emulatorReturnPoseWaitMs else physicalReturnPoseWaitMs

    fun calibrationTimeoutMs(isEmulator: Boolean): Long =
        if (isEmulator) emulatorCalibrationTimeoutMs else physicalCalibrationTimeoutMs

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
        const val VERSION = "mediapipe-lite-calibration-fallback-v9"
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
