package com.kren.michizure.pose

import kotlin.math.max
import kotlin.math.min

/**
 * Temporal squat detector based only on same-side hip/knee vertical geometry.
 *
 * Calibration establishes the standing hip-to-knee gap. Every later frame is
 * expressed as gapRatio and hipDrop relative to that stable baseline.
 */
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
    private var invalidSinceMs: Long? = null
    private var calibrationStartedMs: Long? = null
    private val calibrationHipYs = mutableListOf<Double>()
    private val calibrationGaps = mutableListOf<Double>()
    private var standingHipY = 0.0
    private var standingGap = 0.0
    private var cycleStartedMs: Long? = null
    private var stateEnteredMs: Long? = null
    private var descendingCandidateSinceMs: Long? = null
    private var bottomCandidateSinceMs: Long? = null
    private var ascendingCandidateSinceMs: Long? = null
    private var standingCandidateSinceMs: Long? = null
    private var lastRepAtMs: Long = Long.MIN_VALUE
    private var minimumGapRatio = 1.0
    private var maximumHipDrop = 0.0
    private var cycleFrames = 0
    private var validCycleFrames = 0
    private var latestRejectReason: String? = null
    private var lastDiagnostics = emptyDiagnostics()

    fun process(result: PoseFeatureResult): SquatDetectorUpdate =
        when (result) {
            is PoseFeatureResult.Invalid -> processInvalid(result)
            is PoseFeatureResult.Valid -> processValid(result)
        }

    fun reset() {
        state = SquatState.CALIBRATING
        repSequence = 0
        rejectedAttempts = 0
        previousTimestampMs = null
        invalidSinceMs = null
        resetCalibration()
        clearCycle()
        latestRejectReason = null
        lastDiagnostics = emptyDiagnostics()
    }

    private fun processInvalid(result: PoseFeatureResult.Invalid): SquatDetectorUpdate {
        if (cycleStartedMs != null) cycleFrames += 1
        val started = invalidSinceMs ?: result.timestampMs.also { invalidSinceMs = it }
        previousTimestampMs = null
        latestRejectReason = result.rejectReason
        if (result.timestampMs - started > config.invalidTrackingGraceMs) {
            rejectActiveCycle("poseLost")
            resetToCalibrating()
        }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                gapRatio = null,
                hipDrop = null,
            )
        return update(result.warning)
    }

    private fun processValid(result: PoseFeatureResult.Valid): SquatDetectorUpdate {
        val sample = result.sample
        val lastTimestamp = previousTimestampMs
        if (lastTimestamp != null && sample.timestampMs <= lastTimestamp) {
            latestRejectReason = "duplicateFrame"
            lastDiagnostics =
                diagnostics(
                    quality = result.quality,
                    gapRatio = normalizedGap(sample),
                    hipDrop = normalizedHipDrop(sample),
                )
            return update()
        }
        if (lastTimestamp != null &&
            sample.timestampMs - lastTimestamp > config.maximumFrameGapMs
        ) {
            rejectActiveCycle("frameGap")
            resetToCalibrating()
        }
        previousTimestampMs = sample.timestampMs
        invalidSinceMs = null

        val gapRatio = normalizedGap(sample)
        val hipDrop = normalizedHipDrop(sample)
        if (cycleStartedMs != null) {
            cycleFrames += 1
            validCycleFrames += 1
            if (gapRatio != null) minimumGapRatio = min(minimumGapRatio, gapRatio)
            if (hipDrop != null) maximumHipDrop = max(maximumHipDrop, hipDrop)
        }

        val update =
            when (state) {
                SquatState.CALIBRATING -> calibrate(sample)
                SquatState.STANDING -> fromStanding(sample)
                SquatState.DESCENDING -> fromDescending(sample)
                SquatState.BOTTOM -> fromBottom(sample)
                SquatState.ASCENDING -> fromAscending(sample)
            }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                gapRatio = normalizedGap(sample),
                hipDrop = normalizedHipDrop(sample),
            )
        return update.copy(diagnostics = lastDiagnostics)
    }

    private fun calibrate(sample: PoseFeatureSample): SquatDetectorUpdate {
        val gap = sample.kneeY - sample.hipY
        if (!gap.isFinite() || gap < config.minimumCalibrationGapRatio) {
            resetCalibration()
            latestRejectReason = "calibrationGapTooSmall"
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        val started = calibrationStartedMs ?: sample.timestampMs.also {
            calibrationStartedMs = it
        }
        calibrationHipYs += sample.hipY
        calibrationGaps += gap
        val gapMedian = median(calibrationGaps)
        val hipDrift =
            (calibrationHipYs.maxOrNull()!! - calibrationHipYs.minOrNull()!!) /
                max(gapMedian, EPSILON)
        val gapDrift =
            (calibrationGaps.maxOrNull()!! - calibrationGaps.minOrNull()!!) /
                max(gapMedian, EPSILON)
        if (hipDrift > config.calibrationMaximumHipDriftRatio ||
            gapDrift > config.calibrationMaximumGapDriftRatio
        ) {
            resetCalibration()
            latestRejectReason = "calibrationMotion"
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.timestampMs - started >= config.calibrationStableMs) {
            standingHipY = median(calibrationHipYs)
            standingGap = gapMedian
            latestRejectReason = null
            transition(SquatState.STANDING, sample.timestampMs)
            return update()
        }
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun fromStanding(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (elapsedSinceLastRep(sample.timestampMs) < config.refractoryMs) return update()
        val gapRatio = normalizedGap(sample) ?: return update()
        val hipDrop = normalizedHipDrop(sample) ?: return update()
        val descending =
            gapRatio <= config.descendingGapRatio &&
                hipDrop >= config.descendingHipDropRatio
        if (!descending) {
            descendingCandidateSinceMs = null
            return update()
        }
        val candidate =
            descendingCandidateSinceMs ?: sample.timestampMs.also {
                descendingCandidateSinceMs = it
            }
        if (sample.timestampMs - candidate < config.descendingStableMs) return update()

        cycleStartedMs = candidate
        cycleFrames = 2
        validCycleFrames = 2
        minimumGapRatio = gapRatio
        maximumHipDrop = hipDrop
        latestRejectReason = null
        transition(SquatState.DESCENDING, sample.timestampMs)
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
        if (!isBottom(sample) ||
            elapsedInState(sample.timestampMs) < config.minimumDescendingMs
        ) {
            bottomCandidateSinceMs = null
            return update()
        }
        val candidate =
            bottomCandidateSinceMs ?: sample.timestampMs.also {
                bottomCandidateSinceMs = it
            }
        if (sample.timestampMs - candidate >= config.bottomStableMs) {
            transition(SquatState.BOTTOM, sample.timestampMs)
        }
        return update()
    }

    private fun fromBottom(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            rejectActiveCycle("repTooSlow")
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        val gapRatio = normalizedGap(sample) ?: return update()
        val hipDrop = normalizedHipDrop(sample) ?: return update()
        val leavingBottom =
            gapRatio >= config.bottomExitGapRatio &&
                hipDrop <= config.bottomExitHipDropRatio
        if (!leavingBottom) {
            ascendingCandidateSinceMs = null
            return update()
        }
        val candidate =
            ascendingCandidateSinceMs ?: sample.timestampMs.also {
                ascendingCandidateSinceMs = it
            }
        if (sample.timestampMs - candidate >= config.ascendingStableMs) {
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
        if (isBottom(sample)) {
            val candidate =
                bottomCandidateSinceMs ?: sample.timestampMs.also {
                    bottomCandidateSinceMs = it
                }
            if (sample.timestampMs - candidate >= config.bottomStableMs) {
                transition(SquatState.BOTTOM, sample.timestampMs)
            }
            standingCandidateSinceMs = null
            return update()
        }
        bottomCandidateSinceMs = null
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
                1.0 - minimumGapRatio >= config.minimumGapCompressionRatio &&
                maximumHipDrop >= config.minimumHipDropRatio &&
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

    private fun isStanding(sample: PoseFeatureSample): Boolean {
        val gapRatio = normalizedGap(sample) ?: return false
        val hipDrop = normalizedHipDrop(sample) ?: return false
        return gapRatio >= config.standingGapRatio &&
            hipDrop <= config.standingMaximumHipDropRatio
    }

    private fun isBottom(sample: PoseFeatureSample): Boolean {
        val gapRatio = normalizedGap(sample) ?: return false
        val hipDrop = normalizedHipDrop(sample) ?: return false
        return gapRatio <= config.bottomGapRatio &&
            hipDrop >= config.bottomHipDropRatio
    }

    private fun normalizedGap(sample: PoseFeatureSample): Double? {
        if (standingGap <= EPSILON || state == SquatState.CALIBRATING) return null
        return (sample.kneeY - sample.hipY) / standingGap
    }

    private fun normalizedHipDrop(sample: PoseFeatureSample): Double? {
        if (standingGap <= EPSILON || state == SquatState.CALIBRATING) return null
        return (sample.hipY - standingHipY) / standingGap
    }

    private fun elapsedInState(timestampMs: Long): Long =
        timestampMs - (stateEnteredMs ?: timestampMs)

    private fun cycleTimedOut(timestampMs: Long): Boolean =
        timestampMs - (cycleStartedMs ?: timestampMs) > config.maximumRepDurationMs

    private fun elapsedSinceLastRep(timestampMs: Long): Long =
        if (lastRepAtMs == Long.MIN_VALUE) Long.MAX_VALUE else timestampMs - lastRepAtMs

    private fun transition(
        next: SquatState,
        timestampMs: Long,
    ) {
        state = next
        stateEnteredMs = timestampMs
        if (next != SquatState.STANDING) descendingCandidateSinceMs = null
        if (next != SquatState.DESCENDING && next != SquatState.ASCENDING) {
            bottomCandidateSinceMs = null
        }
        if (next != SquatState.BOTTOM) ascendingCandidateSinceMs = null
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
        previousTimestampMs = null
    }

    private fun resetCalibration() {
        calibrationStartedMs = null
        calibrationHipYs.clear()
        calibrationGaps.clear()
    }

    private fun clearCycle() {
        cycleStartedMs = null
        descendingCandidateSinceMs = null
        bottomCandidateSinceMs = null
        ascendingCandidateSinceMs = null
        standingCandidateSinceMs = null
        minimumGapRatio = 1.0
        maximumHipDrop = 0.0
        cycleFrames = 0
        validCycleFrames = 0
    }

    private fun diagnostics(
        quality: PoseQualityMetrics,
        gapRatio: Double?,
        hipDrop: Double?,
    ) = SquatFrameDiagnostics(
        poseDetected = quality.poseDetected,
        trackingStatus = quality.trackingStatus,
        selectedSide = quality.selectedSide,
        leftHipConfidence = quality.leftHipConfidence,
        leftKneeConfidence = quality.leftKneeConfidence,
        leftAnkleConfidence = quality.leftAnkleConfidence,
        rightHipConfidence = quality.rightHipConfidence,
        rightKneeConfidence = quality.rightKneeConfidence,
        rightAnkleConfidence = quality.rightAnkleConfidence,
        normalizedVerticalGap = gapRatio,
        normalizedHipDrop = hipDrop,
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
            trackingStatus = PoseTrackingStatus.NO_POSE,
            selectedSide = null,
            leftHipConfidence = null,
            leftKneeConfidence = null,
            leftAnkleConfidence = null,
            rightHipConfidence = null,
            rightKneeConfidence = null,
            rightAnkleConfidence = null,
            normalizedVerticalGap = null,
            normalizedHipDrop = null,
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

    private companion object {
        const val EPSILON = 1e-6
    }
}
