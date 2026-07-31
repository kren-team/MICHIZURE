package com.kren.michizure.pose

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Timestamp-driven squat detector.
 *
 * A delayed callback invalidates velocity only. It does not erase calibrated
 * position or an in-progress phase. Only sustained loss of a usable pose resets
 * the cycle and calibration.
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

    private var lastObservedTimestampMs: Long? = null
    private var lastValidTimestampMs: Long? = null
    private var previousKnee: Double? = null
    private var previousHipY: Double? = null

    private var calibrationStartedMs: Long? = null
    private var calibrationSide: PoseSide? = null
    private val calibrationHipYs = ArrayDeque<Double>()
    private val calibrationLegLengths = ArrayDeque<Double>()
    private val calibrationKnees = ArrayDeque<Double>()
    private var calibrationStatus = "waitingForStanding"
    private var standingHipY = 0.0
    private var standingLegLength = 1.0
    private var standingKneeAngle = 180.0
    private var baselineJitter = 0.0

    private var cycleStartedMs: Long? = null
    private var stateEnteredMs: Long? = null
    private var descendingCandidateSinceMs: Long? = null
    private var bottomCandidateSinceMs: Long? = null
    private var ascendingCandidateSinceMs: Long? = null
    private var standingCandidateSinceMs: Long? = null
    private var lastRepAtMs = Long.MIN_VALUE
    private var minimumKnee = 180.0
    private var maximumKnee = 0.0
    private var maximumHipDrop = 0.0
    private var bottomReached = false

    private var previousState: SquatState? = null
    private var lastTransitionReason: String? = null
    private var latestRejectReason: String? = null
    private var lastResetReason: String? = null
    private var currentFrameDtMs: Long? = null
    private val validPoseTimesMs = ArrayDeque<Long>()
    private var lastDiagnostics = emptyDiagnostics()

    fun process(result: PoseFeatureResult): SquatDetectorUpdate {
        val lastObserved = lastObservedTimestampMs
        if (lastObserved != null && result.timestampMs <= lastObserved) {
            latestRejectReason = "duplicateFrame"
            currentFrameDtMs = result.timestampMs - lastObserved
            lastDiagnostics =
                diagnostics(
                    quality = result.quality,
                    filteredKnee = null,
                    rawKnee = null,
                    hipDrop = null,
                    kneeVelocity = null,
                    hipVelocity = null,
                    timestampMs = result.timestampMs,
                )
            return update()
        }
        currentFrameDtMs = lastObserved?.let { result.timestampMs - it }
        lastObservedTimestampMs = result.timestampMs
        return when (result) {
            is PoseFeatureResult.Invalid -> processInvalid(result)
            is PoseFeatureResult.Valid -> processValid(result)
        }
    }

    fun reset() {
        state = SquatState.CALIBRATING
        repSequence = 0
        rejectedAttempts = 0
        lastObservedTimestampMs = null
        lastValidTimestampMs = null
        previousKnee = null
        previousHipY = null
        resetCalibration()
        clearCycle()
        previousState = null
        lastTransitionReason = null
        latestRejectReason = null
        lastResetReason = "sessionReset"
        currentFrameDtMs = null
        validPoseTimesMs.clear()
        lastDiagnostics = emptyDiagnostics()
    }

    private fun processInvalid(result: PoseFeatureResult.Invalid): SquatDetectorUpdate {
        latestRejectReason = result.rejectReason
        val lastValid = lastValidTimestampMs
        if (lastValid != null && result.timestampMs - lastValid > config.poseLossResetMs) {
            rejectActiveCycle("poseLost")
            resetToCalibrating("poseLoss")
        }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                filteredKnee = null,
                rawKnee = null,
                hipDrop = null,
                kneeVelocity = null,
                hipVelocity = null,
                timestampMs = result.timestampMs,
            )
        return update(result.warning)
    }

    private fun processValid(result: PoseFeatureResult.Valid): SquatDetectorUpdate {
        val sample = result.sample
        val lastValid = lastValidTimestampMs
        val validGapMs = lastValid?.let { sample.timestampMs - it }
        val velocityUsable = validGapMs != null && validGapMs in 1..config.velocityResetGapMs
        val elapsedSeconds = validGapMs?.coerceIn(1, config.velocityResetGapMs)?.div(1_000.0)
        val kneeVelocity =
            if (!velocityUsable || previousKnee == null || elapsedSeconds == null) {
                null
            } else {
                (sample.kneeAngleDeg - requireNotNull(previousKnee)) / elapsedSeconds
            }
        val hipVelocity =
            if (!velocityUsable || previousHipY == null || elapsedSeconds == null) {
                null
            } else {
                ((sample.hipY - requireNotNull(previousHipY)) /
                    max(sample.legLength, EPSILON)) / elapsedSeconds
            }

        lastValidTimestampMs = sample.timestampMs
        previousKnee = sample.kneeAngleDeg
        previousHipY = sample.hipY
        recordValidPoseTime(sample.timestampMs)

        if (cycleStartedMs != null) {
            minimumKnee = min(minimumKnee, sample.kneeAngleDeg)
            maximumKnee = max(maximumKnee, sample.kneeAngleDeg)
            maximumHipDrop = max(maximumHipDrop, normalizedHipDrop(sample) ?: 0.0)
        }

        val detectorUpdate =
            when (state) {
                SquatState.CALIBRATING -> calibrate(sample)
                SquatState.STANDING -> fromStanding(sample)
                SquatState.DESCENDING -> fromDescending(sample)
                SquatState.BOTTOM -> fromBottom(sample, kneeVelocity, hipVelocity)
                SquatState.ASCENDING -> fromAscending(sample)
            }
        lastDiagnostics =
            diagnostics(
                quality = result.quality,
                filteredKnee = sample.kneeAngleDeg,
                rawKnee = sample.rawKneeAngleDeg,
                hipDrop = normalizedHipDrop(sample),
                kneeVelocity = kneeVelocity,
                hipVelocity = hipVelocity,
                timestampMs = sample.timestampMs,
            )
        return detectorUpdate.copy(diagnostics = lastDiagnostics)
    }

    private fun calibrate(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (calibrationSide != null && calibrationSide != sample.selectedSide) {
            resetCalibration()
            lastResetReason = "calibrationSideChanged"
        }
        calibrationSide = sample.selectedSide
        if (sample.kneeAngleDeg < config.standingKneeDeg) {
            calibrationStatus = "waitingForStanding"
            expireCalibrationIfNeeded(sample.timestampMs)
            latestRejectReason = "notStandingForCalibration"
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }

        val started = calibrationStartedMs ?: sample.timestampMs.also { calibrationStartedMs = it }
        addCalibrationSample(sample)
        calibrationStatus = "collecting"
        val legMedian = median(calibrationLegLengths)
        val hipJitter = robustSpread(calibrationHipYs) / max(legMedian, EPSILON)
        val kneeJitter = robustSpread(calibrationKnees)
        val stable =
            hipJitter <= config.calibrationMaximumHipDriftRatio &&
                kneeJitter <= config.calibrationMaximumKneeDriftDeg
        val enoughSamples = calibrationKnees.size >= config.calibrationMinimumSamples
        val observedLongEnough = sample.timestampMs - started >= config.calibrationObservationMs

        if (enoughSamples && observedLongEnough && stable) {
            standingHipY = median(calibrationHipYs)
            standingLegLength = legMedian
            standingKneeAngle = median(calibrationKnees)
            baselineJitter = max(hipJitter, kneeJitter / 180.0)
            calibrationStatus = "complete"
            latestRejectReason = null
            transition(SquatState.STANDING, sample.timestampMs, "calibrationComplete")
            return update()
        }
        if (!stable) {
            calibrationStatus = "unstable"
            latestRejectReason = "calibrationMotion"
        }
        expireCalibrationIfNeeded(sample.timestampMs)
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun fromStanding(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (elapsedSinceLastRep(sample.timestampMs) < config.refractoryMs) return update()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        val descendingThreshold =
            min(config.descendingKneeDeg, standingKneeAngle - config.descendingKneeBaselineDeltaDeg)
        val descending =
            sample.kneeAngleDeg < descendingThreshold || hipDrop > config.descendingHipDropRatio
        if (!descending) {
            descendingCandidateSinceMs = null
            return update()
        }
        val candidate = descendingCandidateSinceMs ?: sample.timestampMs.also {
            descendingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate < config.descendingStableMs) return update()
        cycleStartedMs = candidate
        minimumKnee = sample.kneeAngleDeg
        maximumKnee = standingKneeAngle
        maximumHipDrop = hipDrop
        bottomReached = false
        latestRejectReason = null
        transition(SquatState.DESCENDING, sample.timestampMs, "descentConfirmed")
        return update()
    }

    private fun fromDescending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (isStanding(sample)) {
            val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
                standingCandidateSinceMs = it
            }
            if (sample.timestampMs - candidate >= config.standingConfirmationMs) {
                rejectActiveCycle("shallowSquat")
                transition(SquatState.STANDING, sample.timestampMs, "shallowReturnToStanding")
                clearCycle()
            }
            return update()
        }
        standingCandidateSinceMs = null

        val deepEnough =
            sample.kneeAngleDeg <= config.bottomKneeDeg &&
                hipDrop >= config.bottomHipDropRatio
        if (!deepEnough || elapsedInState(sample.timestampMs) < config.minimumDescendingMs) {
            bottomCandidateSinceMs = null
            return update(PoseQualityWarning.SQUAT_DEEPER)
        }
        val candidate = bottomCandidateSinceMs ?: sample.timestampMs.also {
            bottomCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate >= config.bottomConfirmationMs) {
            bottomReached = true
            transition(SquatState.BOTTOM, sample.timestampMs, "bottomConfirmed")
        }
        return update(if (isVeryDeep(sample, hipDrop)) PoseQualityWarning.TOO_DEEP else null)
    }

    private fun fromBottom(
        sample: PoseFeatureSample,
        kneeVelocity: Double?,
        hipVelocity: Double?,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        val positionExitedBottom =
            sample.kneeAngleDeg >= config.bottomExitKneeDeg ||
                hipDrop <= config.bottomExitMaximumHipDropRatio
        val movingUp =
            (kneeVelocity != null && kneeVelocity > 0.0) ||
                (hipVelocity != null && hipVelocity < 0.0)
        if (!positionExitedBottom || (kneeVelocity != null && hipVelocity != null && !movingUp)) {
            ascendingCandidateSinceMs = null
            return update(if (isVeryDeep(sample, hipDrop)) PoseQualityWarning.TOO_DEEP else null)
        }
        val candidate = ascendingCandidateSinceMs ?: sample.timestampMs.also {
            ascendingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate >= config.ascendingStableMs) {
            transition(SquatState.ASCENDING, sample.timestampMs, "ascentConfirmed")
        }
        return update()
    }

    private fun fromAscending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (sample.kneeAngleDeg <= config.bottomKneeDeg && hipDrop >= config.bottomHipDropRatio) {
            transition(SquatState.BOTTOM, sample.timestampMs, "returnedToBottom")
            return update()
        }
        if (!isReturnStanding(sample)) {
            standingCandidateSinceMs = null
            return update()
        }
        val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
            standingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate < config.returnStandingConfirmationMs) return update()

        val totalDuration = sample.timestampMs - requireNotNull(cycleStartedMs)
        val ascendingDuration = sample.timestampMs - requireNotNull(stateEnteredMs)
        val validRep =
            bottomReached &&
                totalDuration in config.minimumRepDurationMs..config.maximumRepDurationMs &&
                ascendingDuration >= config.minimumAscendingMs &&
                maximumKnee - minimumKnee >= config.minimumRangeOfMotionDeg &&
                maximumHipDrop >= config.minimumRepHipDropRatio &&
                elapsedSinceLastRep(sample.timestampMs) >= config.refractoryMs

        transition(SquatState.STANDING, sample.timestampMs, "returnStandingConfirmed")
        clearCycle()
        if (!validRep) {
            rejectedAttempts += 1
            latestRejectReason =
                if (totalDuration < config.minimumRepDurationMs) "repTooFast" else "incompleteRange"
            return update()
        }
        latestRejectReason = null
        lastRepAtMs = sample.timestampMs
        repSequence += 1
        lastTransitionReason = "repAccepted"
        return update(repCompleted = true)
    }

    private fun timeout(): SquatDetectorUpdate {
        rejectActiveCycle("repTooSlow")
        resetToCalibrating("repTimeout")
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun isVeryDeep(sample: PoseFeatureSample, hipDrop: Double): Boolean =
        sample.kneeAngleDeg <= config.tooDeepKneeDeg && hipDrop >= config.tooDeepHipDropRatio

    private fun isStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >=
            max(config.standingKneeDeg, standingKneeAngle - config.standingKneeBaselineToleranceDeg) &&
            (normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY) <=
            config.standingMaximumHipDropRatio

    private fun isReturnStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >= config.returnStandingKneeDeg &&
            (normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY) <=
            config.returnStandingMaximumHipDropRatio

    private fun normalizedHipDrop(sample: PoseFeatureSample): Double? {
        if (standingLegLength <= EPSILON || state == SquatState.CALIBRATING) return null
        return (sample.hipY - standingHipY) / standingLegLength
    }

    private fun addCalibrationSample(sample: PoseFeatureSample) {
        calibrationHipYs.addLast(sample.hipY)
        calibrationLegLengths.addLast(sample.legLength)
        calibrationKnees.addLast(sample.kneeAngleDeg)
        while (calibrationKnees.size > config.calibrationTargetSamples) {
            calibrationHipYs.removeFirst()
            calibrationLegLengths.removeFirst()
            calibrationKnees.removeFirst()
        }
    }

    private fun expireCalibrationIfNeeded(timestampMs: Long) {
        val started = calibrationStartedMs ?: return
        if (timestampMs - started <= config.calibrationTimeoutMs) return
        resetCalibration()
        calibrationStatus = "timedOut"
        lastResetReason = "calibrationTimeout"
    }

    private fun recordValidPoseTime(timestampMs: Long) {
        validPoseTimesMs.addLast(timestampMs)
        while (validPoseTimesMs.isNotEmpty() && timestampMs - validPoseTimesMs.first() > FPS_WINDOW_MS) {
            validPoseTimesMs.removeFirst()
        }
    }

    private fun effectiveValidPoseFps(): Double {
        if (validPoseTimesMs.size < 2) return 0.0
        val duration = validPoseTimesMs.last() - validPoseTimesMs.first()
        return if (duration <= 0) 0.0 else (validPoseTimesMs.size - 1) * 1_000.0 / duration
    }

    private fun elapsedInState(timestampMs: Long): Long = timestampMs - (stateEnteredMs ?: timestampMs)

    private fun cycleTimedOut(timestampMs: Long): Boolean =
        timestampMs - (cycleStartedMs ?: timestampMs) > config.maximumRepDurationMs

    private fun elapsedSinceLastRep(timestampMs: Long): Long =
        if (lastRepAtMs == Long.MIN_VALUE) Long.MAX_VALUE else timestampMs - lastRepAtMs

    private fun transition(next: SquatState, timestampMs: Long, reason: String) {
        previousState = state
        state = next
        stateEnteredMs = timestampMs
        lastTransitionReason = reason
        when (next) {
            SquatState.CALIBRATING -> Unit
            SquatState.STANDING -> {
                descendingCandidateSinceMs = null
                bottomCandidateSinceMs = null
                ascendingCandidateSinceMs = null
                standingCandidateSinceMs = null
            }
            SquatState.DESCENDING -> {
                descendingCandidateSinceMs = null
                bottomCandidateSinceMs = null
                standingCandidateSinceMs = null
            }
            SquatState.BOTTOM -> {
                bottomCandidateSinceMs = null
                ascendingCandidateSinceMs = null
            }
            SquatState.ASCENDING -> {
                ascendingCandidateSinceMs = null
                standingCandidateSinceMs = null
            }
        }
    }

    private fun rejectActiveCycle(reason: String) {
        if (cycleStartedMs != null) {
            rejectedAttempts += 1
            latestRejectReason = reason
        }
    }

    private fun resetToCalibrating(reason: String) {
        previousState = state
        state = SquatState.CALIBRATING
        stateEnteredMs = null
        lastTransitionReason = "resetToCalibrating"
        lastResetReason = reason
        resetCalibration()
        clearCycle()
        previousKnee = null
        previousHipY = null
        lastValidTimestampMs = null
    }

    private fun resetCalibration() {
        calibrationStartedMs = null
        calibrationSide = null
        calibrationHipYs.clear()
        calibrationLegLengths.clear()
        calibrationKnees.clear()
        calibrationStatus = "waitingForStanding"
    }

    private fun clearCycle() {
        cycleStartedMs = null
        descendingCandidateSinceMs = null
        bottomCandidateSinceMs = null
        ascendingCandidateSinceMs = null
        standingCandidateSinceMs = null
        minimumKnee = 180.0
        maximumKnee = 0.0
        maximumHipDrop = 0.0
        bottomReached = false
    }

    private fun diagnostics(
        quality: PoseQualityMetrics,
        filteredKnee: Double?,
        rawKnee: Double?,
        hipDrop: Double?,
        kneeVelocity: Double?,
        hipVelocity: Double?,
        timestampMs: Long,
    ) = SquatFrameDiagnostics(
        poseDetected = quality.poseDetected,
        selectedSide = quality.selectedSide,
        leftHipConfidence = quality.leftHipConfidence,
        leftKneeConfidence = quality.leftKneeConfidence,
        leftAnkleConfidence = quality.leftAnkleConfidence,
        rightHipConfidence = quality.rightHipConfidence,
        rightKneeConfidence = quality.rightKneeConfidence,
        rightAnkleConfidence = quality.rightAnkleConfidence,
        kneeAngleDeg = filteredKnee,
        rawKneeAngleDeg = rawKnee,
        normalizedHipDrop = hipDrop,
        kneeAngularVelocity = kneeVelocity,
        hipVerticalVelocity = hipVelocity,
        latestRejectReason = latestRejectReason,
        rejectedAttempts = rejectedAttempts,
        trackingStatus = quality.trackingStatus,
        previousState = previousState,
        lastTransitionReason = lastTransitionReason,
        lastResetReason = lastResetReason,
        frameDtMs = currentFrameDtMs,
        validPoseAgeMs = lastValidTimestampMs?.let { (timestampMs - it).coerceAtLeast(0) },
        effectiveValidPoseFps = effectiveValidPoseFps(),
        calibrationSampleCount = calibrationKnees.size,
        calibrationStatus = calibrationStatus,
        bottomReached = bottomReached,
        standingConfirmationDurationMs = candidateDuration(standingCandidateSinceMs, timestampMs),
        bottomConfirmationDurationMs = candidateDuration(bottomCandidateSinceMs, timestampMs),
        returnStandingDurationMs =
            if (state == SquatState.ASCENDING) candidateDuration(standingCandidateSinceMs, timestampMs) else 0,
        currentRepDurationMs = cycleStartedMs?.let { (timestampMs - it).coerceAtLeast(0) },
        standingThresholdDeg = config.standingKneeDeg,
        bottomThresholdDeg = config.bottomKneeDeg,
    )

    private fun candidateDuration(startedMs: Long?, timestampMs: Long): Long =
        startedMs?.let { (timestampMs - it).coerceAtLeast(0) } ?: 0

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

    private fun emptyDiagnostics() = SquatFrameDiagnostics(
        poseDetected = false,
        selectedSide = null,
        leftHipConfidence = null,
        leftKneeConfidence = null,
        leftAnkleConfidence = null,
        rightHipConfidence = null,
        rightKneeConfidence = null,
        rightAnkleConfidence = null,
        kneeAngleDeg = null,
        rawKneeAngleDeg = null,
        normalizedHipDrop = null,
        kneeAngularVelocity = null,
        hipVerticalVelocity = null,
        latestRejectReason = null,
        rejectedAttempts = 0,
        trackingStatus = PoseTrackingStatus.NO_POSE,
        previousState = null,
        lastTransitionReason = null,
        lastResetReason = null,
        frameDtMs = null,
        validPoseAgeMs = null,
        effectiveValidPoseFps = 0.0,
        calibrationSampleCount = 0,
        calibrationStatus = "waitingForStanding",
        bottomReached = false,
        standingConfirmationDurationMs = 0,
        bottomConfirmationDurationMs = 0,
        returnStandingDurationMs = 0,
        currentRepDurationMs = null,
        standingThresholdDeg = config.standingKneeDeg,
        bottomThresholdDeg = config.bottomKneeDeg,
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

    private fun robustSpread(values: Collection<Double>): Double {
        if (values.isEmpty()) return Double.POSITIVE_INFINITY
        val center = median(values)
        return median(values.map { abs(it - center) }) * MAD_TO_SIGMA
    }

    private companion object {
        const val EPSILON = 1e-6
        const val FPS_WINDOW_MS = 3_000L
        const val MAD_TO_SIGMA = 1.4826
    }
}
