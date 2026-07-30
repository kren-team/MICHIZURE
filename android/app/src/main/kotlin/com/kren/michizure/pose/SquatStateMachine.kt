package com.kren.michizure.pose

import kotlin.math.max
import kotlin.math.min

class SquatStateMachine(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    var state: SquatState = SquatState.CALIBRATING
        private set

    var repSequence: Int = 0
        private set

    var rejectedAttempts: Int = 0
        private set

    private var previousTimestampMs: Long? = null
    private var previousKnee: Double? = null
    private var previousHipY: Double? = null
    private var invalidSinceMs: Long? = null
    private var calibrationStartedMs: Long? = null
    private val calibrationHipYs = mutableListOf<Double>()
    private val calibrationLegLengths = mutableListOf<Double>()
    private val calibrationKnees = mutableListOf<Double>()
    private var standingHipY = 0.0
    private var standingLegLength = 1.0
    private var standingKneeAngle = 180.0
    private var cycleStartedMs: Long? = null
    private var stateEnteredMs: Long? = null
    private var bottomCandidateSinceMs: Long? = null
    private var standingCandidateSinceMs: Long? = null
    private var lastRepAtMs: Long = Long.MIN_VALUE
    private var minimumKnee = 180.0
    private var maximumKnee = 0.0
    private var cycleFrames = 0
    private var validCycleFrames = 0
    private var latestRejectReason: String? = null
    private var lastDiagnostics = emptyDiagnostics()

    fun process(result: PoseFeatureResult): SquatDetectorUpdate {
        return when (result) {
            is PoseFeatureResult.Invalid -> processInvalid(result)
            is PoseFeatureResult.Valid -> processValid(result)
        }
    }

    fun reset() {
        state = SquatState.CALIBRATING
        repSequence = 0
        rejectedAttempts = 0
        previousTimestampMs = null
        previousKnee = null
        previousHipY = null
        invalidSinceMs = null
        resetCalibration()
        clearCycle()
        latestRejectReason = null
        lastDiagnostics = emptyDiagnostics()
    }

    private fun processInvalid(result: PoseFeatureResult.Invalid): SquatDetectorUpdate {
        if (cycleStartedMs != null) cycleFrames += 1
        val started = invalidSinceMs ?: result.timestampMs.also { invalidSinceMs = it }
        previousKnee = null
        previousHipY = null
        previousTimestampMs = null
        latestRejectReason = result.rejectReason
        if (result.timestampMs - started > config.invalidTrackingGraceMs) {
            rejectActiveCycle("poseLost")
            resetToCalibrating()
        }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                knee = null,
                hipDrop = null,
                kneeVelocity = null,
                hipVelocity = null,
            )
        return update(warning = result.warning)
    }

    private fun processValid(result: PoseFeatureResult.Valid): SquatDetectorUpdate {
        val raw = result.sample
        val lastTimestamp = previousTimestampMs
        if (lastTimestamp != null && raw.timestampMs <= lastTimestamp) {
            latestRejectReason = "duplicateFrame"
            lastDiagnostics =
                diagnostics(
                    quality = result.quality,
                    knee = raw.kneeAngleDeg,
                    hipDrop = normalizedHipDrop(raw),
                    kneeVelocity = null,
                    hipVelocity = null,
                )
            return update()
        }
        if (lastTimestamp != null &&
            raw.timestampMs - lastTimestamp > config.maximumFrameGapMs
        ) {
            rejectActiveCycle("frameGap")
            resetToCalibrating()
        }
        invalidSinceMs = null
        val sample = raw
        val priorKnee = previousKnee
        val priorHipY = previousHipY
        val priorTimestamp = previousTimestampMs
        val elapsedSeconds =
            if (priorTimestamp == null) null else (sample.timestampMs - priorTimestamp) / 1_000.0
        val kneeVelocity =
            if (priorKnee == null || elapsedSeconds == null || elapsedSeconds <= 0) {
                0.0
            } else {
                (sample.kneeAngleDeg - priorKnee) / elapsedSeconds
            }
        val hipVelocity =
            if (priorHipY == null || elapsedSeconds == null || elapsedSeconds <= 0) {
                0.0
            } else {
                ((sample.hipY - priorHipY) / max(sample.legLength, 1e-6)) /
                    elapsedSeconds
            }
        previousKnee = sample.kneeAngleDeg
        previousHipY = sample.hipY
        previousTimestampMs = sample.timestampMs

        if (cycleStartedMs != null) {
            cycleFrames += 1
            validCycleFrames += 1
            minimumKnee = min(minimumKnee, sample.kneeAngleDeg)
            maximumKnee = max(maximumKnee, sample.kneeAngleDeg)
        }

        val update =
            when (state) {
                SquatState.CALIBRATING -> calibrate(sample)
                SquatState.STANDING -> fromStanding(sample, kneeVelocity, hipVelocity)
                SquatState.DESCENDING -> fromDescending(sample)
                SquatState.BOTTOM -> fromBottom(sample, kneeVelocity, hipVelocity)
                SquatState.ASCENDING -> fromAscending(sample)
            }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                knee = sample.kneeAngleDeg,
                hipDrop = normalizedHipDrop(sample),
                kneeVelocity = kneeVelocity,
                hipVelocity = hipVelocity,
            )
        return update.copy(diagnostics = lastDiagnostics)
    }

    private fun calibrate(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (sample.kneeAngleDeg < config.standingKneeDeg) {
            resetCalibration()
            latestRejectReason = "notStandingForCalibration"
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        val started = calibrationStartedMs ?: sample.timestampMs.also {
            calibrationStartedMs = it
        }
        calibrationHipYs += sample.hipY
        calibrationLegLengths += sample.legLength
        calibrationKnees += sample.kneeAngleDeg
        val legMedian = median(calibrationLegLengths)
        val hipDrift =
            (calibrationHipYs.maxOrNull()!! - calibrationHipYs.minOrNull()!!) /
                max(legMedian, 1e-6)
        val kneeDrift =
            calibrationKnees.maxOrNull()!! - calibrationKnees.minOrNull()!!
        if (hipDrift > config.calibrationMaximumHipDriftRatio ||
            kneeDrift > config.calibrationMaximumKneeDriftDeg
        ) {
            resetCalibration()
            latestRejectReason = "calibrationMotion"
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.timestampMs - started >= config.calibrationStableMs) {
            standingHipY = median(calibrationHipYs)
            standingLegLength = legMedian
            standingKneeAngle = median(calibrationKnees)
            latestRejectReason = null
            transition(SquatState.STANDING, sample.timestampMs)
            return update()
        }
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun fromStanding(
        sample: PoseFeatureSample,
        kneeVelocity: Double,
        hipVelocity: Double,
    ): SquatDetectorUpdate {
        if (elapsedSinceLastRep(sample.timestampMs) < config.refractoryMs) {
            return update()
        }
        val descendingThreshold =
            min(
                config.descendingKneeDeg,
                standingKneeAngle - config.descendingKneeBaselineDeltaDeg,
            )
        if (sample.kneeAngleDeg < descendingThreshold &&
            kneeVelocity < -config.minimumMovementVelocityDegPerSec &&
            hipVelocity > config.minimumHipVelocityRatioPerSec
        ) {
            cycleStartedMs = sample.timestampMs
            cycleFrames = 1
            validCycleFrames = 1
            minimumKnee = sample.kneeAngleDeg
            maximumKnee = standingKneeAngle
            latestRejectReason = null
            transition(SquatState.DESCENDING, sample.timestampMs)
        }
        return update()
    }

    private fun fromDescending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            rejectActiveCycle("repTooSlow")
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (isStanding(sample)) {
            rejectActiveCycle("shallowSquat")
            transition(SquatState.STANDING, sample.timestampMs)
            clearCycle()
            return update()
        }
        val deepEnough =
            sample.kneeAngleDeg <= config.bottomKneeDeg &&
                (normalizedHipDrop(sample) ?: 0.0) >= config.bottomHipDropRatio
        if (deepEnough &&
            elapsedInState(sample.timestampMs) >= config.minimumDescendingMs
        ) {
            val candidate =
                bottomCandidateSinceMs ?: sample.timestampMs.also {
                    bottomCandidateSinceMs = it
                }
            if (sample.timestampMs - candidate >= config.bottomStableMs) {
                transition(SquatState.BOTTOM, sample.timestampMs)
            }
        } else {
            bottomCandidateSinceMs = null
        }
        return update()
    }

    private fun fromBottom(
        sample: PoseFeatureSample,
        kneeVelocity: Double,
        hipVelocity: Double,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            rejectActiveCycle("repTooSlow")
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.kneeAngleDeg >= config.bottomExitKneeDeg &&
            kneeVelocity > config.minimumMovementVelocityDegPerSec &&
            hipVelocity < -config.minimumHipVelocityRatioPerSec
        ) {
            transition(SquatState.ASCENDING, sample.timestampMs)
        }
        return update()
    }

    private fun fromAscending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            rejectActiveCycle("repTooSlow")
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.kneeAngleDeg <= config.bottomKneeDeg) {
            transition(SquatState.BOTTOM, sample.timestampMs)
            standingCandidateSinceMs = null
            return update()
        }
        if (!isStanding(sample)) {
            standingCandidateSinceMs = null
            return update()
        }
        val candidate =
            standingCandidateSinceMs ?: sample.timestampMs.also {
                standingCandidateSinceMs = it
            }
        if (sample.timestampMs - candidate < config.standingStableMs) return update()

        val started = requireNotNull(cycleStartedMs)
        val totalDuration = sample.timestampMs - started
        val ascendingDuration = sample.timestampMs - requireNotNull(stateEnteredMs)
        val validRatio =
            if (cycleFrames == 0) 0.0 else validCycleFrames.toDouble() / cycleFrames
        val validRep =
            totalDuration in config.minimumRepDurationMs..config.maximumRepDurationMs &&
                ascendingDuration >= config.minimumAscendingMs &&
                maximumKnee - minimumKnee >= config.minimumRangeOfMotionDeg &&
                validRatio >= config.minimumValidFrameRatio &&
                elapsedSinceLastRep(sample.timestampMs) >= config.refractoryMs
        transition(SquatState.STANDING, sample.timestampMs)
        clearCycle()
        if (!validRep) {
            rejectedAttempts += 1
            latestRejectReason =
                if (totalDuration < config.minimumRepDurationMs) {
                    "repTooFast"
                } else {
                    "incompleteRange"
                }
            return update()
        }
        latestRejectReason = null
        lastRepAtMs = sample.timestampMs
        repSequence += 1
        return update(repCompleted = true)
    }

    private fun isStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >=
            max(
                config.standingKneeDeg,
                standingKneeAngle - config.standingKneeBaselineToleranceDeg,
            )

    private fun normalizedHipDrop(sample: PoseFeatureSample): Double? {
        if (standingLegLength <= 1e-6 || state == SquatState.CALIBRATING) return null
        return (sample.hipY - standingHipY) / standingLegLength
    }

    private fun elapsedInState(timestampMs: Long): Long =
        timestampMs - (stateEnteredMs ?: timestampMs)

    private fun cycleTimedOut(timestampMs: Long): Boolean =
        timestampMs - (cycleStartedMs ?: timestampMs) > config.maximumRepDurationMs

    private fun elapsedSinceLastRep(timestampMs: Long): Long =
        if (lastRepAtMs == Long.MIN_VALUE) Long.MAX_VALUE else timestampMs - lastRepAtMs

    private fun transition(next: SquatState, timestampMs: Long) {
        state = next
        stateEnteredMs = timestampMs
        if (next != SquatState.DESCENDING) bottomCandidateSinceMs = null
        if (next != SquatState.ASCENDING) standingCandidateSinceMs = null
    }

    private fun rejectActiveCycle(reason: String) {
        if (cycleStartedMs != null) {
            rejectedAttempts += 1
            latestRejectReason = reason
        }
    }

    private fun resetToCalibrating() {
        state = SquatState.CALIBRATING
        stateEnteredMs = null
        resetCalibration()
        clearCycle()
        previousKnee = null
        previousHipY = null
        previousTimestampMs = null
    }

    private fun resetCalibration() {
        calibrationStartedMs = null
        calibrationHipYs.clear()
        calibrationLegLengths.clear()
        calibrationKnees.clear()
    }

    private fun clearCycle() {
        cycleStartedMs = null
        bottomCandidateSinceMs = null
        standingCandidateSinceMs = null
        minimumKnee = 180.0
        maximumKnee = 0.0
        cycleFrames = 0
        validCycleFrames = 0
    }

    private fun diagnostics(
        quality: PoseQualityMetrics,
        knee: Double?,
        hipDrop: Double?,
        kneeVelocity: Double?,
        hipVelocity: Double?,
    ) = SquatFrameDiagnostics(
        poseDetected = quality.poseDetected,
        selectedSide = quality.selectedSide,
        leftHipConfidence = quality.leftHipConfidence,
        leftKneeConfidence = quality.leftKneeConfidence,
        leftAnkleConfidence = quality.leftAnkleConfidence,
        rightHipConfidence = quality.rightHipConfidence,
        rightKneeConfidence = quality.rightKneeConfidence,
        rightAnkleConfidence = quality.rightAnkleConfidence,
        kneeAngleDeg = knee,
        normalizedHipDrop = hipDrop,
        kneeAngularVelocity = kneeVelocity,
        hipVerticalVelocity = hipVelocity,
        latestRejectReason = latestRejectReason,
        rejectedAttempts = rejectedAttempts,
    )

    private fun update(
        warning: PoseQualityWarning? = null,
        repCompleted: Boolean = false,
    ) = SquatDetectorUpdate(
        state = state,
        qualityWarning = warning,
        repCompleted = repCompleted,
        repSequence = repSequence,
        diagnostics = lastDiagnostics,
    )

    private fun emptyDiagnostics() =
        SquatFrameDiagnostics(
            poseDetected = false,
            selectedSide = null,
            leftHipConfidence = null,
            leftKneeConfidence = null,
            leftAnkleConfidence = null,
            rightHipConfidence = null,
            rightKneeConfidence = null,
            rightAnkleConfidence = null,
            kneeAngleDeg = null,
            normalizedHipDrop = null,
            kneeAngularVelocity = null,
            hipVerticalVelocity = null,
            latestRejectReason = null,
            rejectedAttempts = 0,
        )

    private fun median(values: Collection<Double>): Double {
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) {
            (sorted[middle - 1] + sorted[middle]) / 2
        } else {
            sorted[middle]
        }
    }
}
