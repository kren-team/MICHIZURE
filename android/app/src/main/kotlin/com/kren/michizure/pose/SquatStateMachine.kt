package com.kren.michizure.pose

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Timestamp-driven squat detector whose depth thresholds are derived from the
 * calibrated standing knee angle.
 *
 * A delayed callback invalidates velocity only. It does not erase calibration,
 * the current phase, or [bottomReached]. Only sustained loss of a usable pose
 * resets the active attempt.
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
    private var calibrationStatus = WAITING_FOR_STANDING
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
            latestRejectReason = REJECT_DUPLICATE_TIMESTAMP
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
        clearCycle(clearAttemptMetrics = true)
        previousState = null
        lastTransitionReason = null
        latestRejectReason = null
        lastResetReason = RESET_SESSION
        currentFrameDtMs = null
        validPoseTimesMs.clear()
        lastDiagnostics = emptyDiagnostics()
    }

    private fun processInvalid(result: PoseFeatureResult.Invalid): SquatDetectorUpdate {
        latestRejectReason = result.rejectReason
        val lastValid = lastValidTimestampMs
        if (lastValid != null && result.timestampMs - lastValid > config.poseLossResetMs) {
            rejectActiveCycle(REJECT_POSE_LOST)
            resetToCalibrating(RESET_POSE_LOST)
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

        val hipDrop = normalizedHipDrop(sample)
        if (cycleStartedMs != null) recordAttempt(sample, hipDrop ?: 0.0)

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
            lastResetReason = RESET_CALIBRATION_SIDE_CHANGED
        }
        calibrationSide = sample.selectedSide
        if (sample.kneeAngleDeg < config.calibrationStandingMinimumKneeDeg) {
            calibrationStatus = WAITING_FOR_STANDING
            expireCalibrationIfNeeded(sample.timestampMs)
            latestRejectReason = WAITING_FOR_STANDING
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }

        val started = calibrationStartedMs ?: sample.timestampMs.also { calibrationStartedMs = it }
        addCalibrationSample(sample)
        calibrationStatus = CALIBRATION_COLLECTING
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
            calibrationStatus = CALIBRATION_COMPLETE
            latestRejectReason = null
            transition(SquatState.STANDING, sample.timestampMs, CALIBRATION_COMPLETE)
            return update()
        }
        if (!stable) {
            calibrationStatus = CALIBRATION_UNSTABLE
            latestRejectReason = REJECT_CALIBRATION_MOTION
        }
        expireCalibrationIfNeeded(sample.timestampMs)
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun fromStanding(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (elapsedSinceLastRep(sample.timestampMs) < config.refractoryMs) {
            latestRejectReason = WAITING_FOR_REFRACTORY
            return update()
        }
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (isBottomCandidate(sample, hipDrop)) {
            beginCycleIfNeeded(sample, hipDrop)
            descendingCandidateSinceMs = null
            return confirmBottom(sample, directFromStanding = true)
        }

        bottomCandidateSinceMs = null
        val thresholds = thresholds()
        val descendingByAngle = sample.kneeAngleDeg < thresholds.descendingStartAngle
        val descendingByHipDrop = hipDrop > config.descendingHipDropRatio
        if (!descendingByAngle && !descendingByHipDrop) {
            descendingCandidateSinceMs = null
            if (cycleStartedMs != null && !bottomReached) clearCycle(clearAttemptMetrics = false)
            latestRejectReason = WAITING_FOR_DESCENT
            return update()
        }

        beginCycleIfNeeded(sample, hipDrop)
        latestRejectReason =
            if (descendingByAngle) DESCENDING_BY_ANGLE else DESCENDING_BY_HIP_DROP
        val candidate = descendingCandidateSinceMs ?: sample.timestampMs.also {
            descendingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate >= config.descendingStableMs) {
            transition(SquatState.DESCENDING, sample.timestampMs, latestRejectReason!!)
        }
        return update()
    }

    private fun fromDescending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (isBottomCandidate(sample, hipDrop)) return confirmBottom(sample)

        bottomCandidateSinceMs = null
        if (isStanding(sample)) {
            val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
                standingCandidateSinceMs = it
            }
            latestRejectReason = REJECT_SHALLOW
            if (sample.timestampMs - candidate >= config.standingConfirmationMs) {
                rejectActiveCycle(REJECT_SHALLOW)
                transition(SquatState.STANDING, sample.timestampMs, REJECT_SHALLOW)
                clearCycle(clearAttemptMetrics = false)
            }
            return update()
        }
        standingCandidateSinceMs = null
        latestRejectReason = missingBottomReason(sample, hipDrop)
        return update(PoseQualityWarning.SQUAT_DEEPER)
    }

    private fun fromBottom(
        sample: PoseFeatureSample,
        kneeVelocity: Double?,
        hipVelocity: Double?,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        if (isReturnStanding(sample)) return confirmReturnStanding(sample)
        standingCandidateSinceMs = null

        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (isBottomCandidate(sample, hipDrop)) {
            ascendingCandidateSinceMs = null
            latestRejectReason = BOTTOM_CONFIRMED
            return update(if (isVeryDeep(sample, hipDrop)) PoseQualityWarning.TOO_DEEP else null)
        }

        val movingUp =
            (kneeVelocity != null && kneeVelocity > 0.0) ||
                (hipVelocity != null && hipVelocity < 0.0)
        val velocityUnavailable = kneeVelocity == null && hipVelocity == null
        val positionExitedBottom =
            sample.kneeAngleDeg > thresholds().bottomAngle ||
                hipDrop < config.bottomHipDropRatio
        if (!movingUp && !(velocityUnavailable && positionExitedBottom)) {
            ascendingCandidateSinceMs = null
            latestRejectReason = WAITING_FOR_ASCENT
            return update()
        }

        val candidate = ascendingCandidateSinceMs ?: sample.timestampMs.also {
            ascendingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate >= config.ascendingStableMs) {
            transition(SquatState.ASCENDING, sample.timestampMs, ASCENDING_CONFIRMED)
        }
        return update()
    }

    private fun fromAscending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        if (isBottomCandidate(sample, hipDrop)) {
            transition(SquatState.BOTTOM, sample.timestampMs, RETURNED_TO_BOTTOM)
            return update(if (isVeryDeep(sample, hipDrop)) PoseQualityWarning.TOO_DEEP else null)
        }
        if (isReturnStanding(sample)) return confirmReturnStanding(sample)

        standingCandidateSinceMs = null
        latestRejectReason = missingReturnReason(sample, hipDrop)
        return update()
    }

    private fun confirmBottom(
        sample: PoseFeatureSample,
        directFromStanding: Boolean = false,
    ): SquatDetectorUpdate {
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        val candidate = bottomCandidateSinceMs ?: sample.timestampMs.also {
            bottomCandidateSinceMs = it
        }
        latestRejectReason = BOTTOM_CONFIRMING
        if (sample.timestampMs - candidate >= config.bottomConfirmationMs) {
            bottomReached = true
            transition(
                SquatState.BOTTOM,
                sample.timestampMs,
                if (directFromStanding) BOTTOM_CONFIRMED_DIRECT else BOTTOM_CONFIRMED,
            )
            latestRejectReason = null
        }
        return update(if (isVeryDeep(sample, hipDrop)) PoseQualityWarning.TOO_DEEP else null)
    }

    private fun confirmReturnStanding(sample: PoseFeatureSample): SquatDetectorUpdate {
        val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
            standingCandidateSinceMs = it
        }
        if (sample.timestampMs - candidate < config.returnStandingConfirmationMs) {
            latestRejectReason = RETURN_STANDING_CONFIRMING
            return update()
        }

        val totalDuration = sample.timestampMs - requireNotNull(cycleStartedMs)
        val durationValid = totalDuration in config.minimumRepDurationMs..config.maximumRepDurationMs
        val refractoryComplete = elapsedSinceLastRep(sample.timestampMs) >= config.refractoryMs
        val validRep = bottomReached && durationValid && refractoryComplete

        if (!validRep) {
            val reason =
                when {
                    !bottomReached -> REJECT_SHALLOW
                    !durationValid -> REJECT_DURATION
                    else -> REJECT_DUPLICATE
                }
            rejectActiveCycle(reason)
            transition(SquatState.STANDING, sample.timestampMs, reason)
            clearCycle(clearAttemptMetrics = false)
            return update()
        }

        lastRepAtMs = sample.timestampMs
        repSequence += 1
        latestRejectReason = null
        transition(SquatState.STANDING, sample.timestampMs, REP_ACCEPTED)
        clearCycle(clearAttemptMetrics = false)
        return update(repCompleted = true)
    }

    private fun timeout(): SquatDetectorUpdate {
        rejectActiveCycle(REJECT_DURATION)
        resetToCalibrating(RESET_REP_TIMEOUT)
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun thresholds(): SquatCalibrationThresholds = config.thresholdsFor(standingKneeAngle)

    private fun isBottomCandidate(sample: PoseFeatureSample, hipDrop: Double): Boolean {
        val bottomAngle = thresholds().bottomAngle
        if (sample.kneeAngleDeg > bottomAngle) return false
        val requiredHipDrop =
            if (sample.kneeAngleDeg <= bottomAngle - config.deepBottomAngleMarginDeg) {
                config.deepBottomMinimumHipDropRatio
            } else {
                config.bottomHipDropRatio
            }
        return hipDrop >= requiredHipDrop
    }

    private fun missingBottomReason(sample: PoseFeatureSample, hipDrop: Double): String {
        val bottomAngle = thresholds().bottomAngle
        if (sample.kneeAngleDeg > bottomAngle) return BOTTOM_ANGLE_NOT_REACHED
        val requiredHipDrop =
            if (sample.kneeAngleDeg <= bottomAngle - config.deepBottomAngleMarginDeg) {
                config.deepBottomMinimumHipDropRatio
            } else {
                config.bottomHipDropRatio
            }
        return if (hipDrop < requiredHipDrop) {
            BOTTOM_HIP_DROP_NOT_REACHED
        } else {
            BOTTOM_CONFIRMING
        }
    }

    private fun missingReturnReason(sample: PoseFeatureSample, hipDrop: Double): String =
        if (sample.kneeAngleDeg < thresholds().returnStandingAngle) {
            RETURN_ANGLE_NOT_REACHED
        } else if (hipDrop > config.returnStandingMaximumHipDropRatio) {
            RETURN_HIP_DROP_NOT_REACHED
        } else {
            RETURN_STANDING_CONFIRMING
        }

    private fun isVeryDeep(sample: PoseFeatureSample, hipDrop: Double): Boolean =
        sample.kneeAngleDeg <= config.tooDeepKneeDeg && hipDrop >= config.tooDeepHipDropRatio

    private fun isReturnStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >= thresholds().returnStandingAngle &&
            (normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY) <=
            config.returnStandingMaximumHipDropRatio

    private fun isStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >= thresholds().standingEnterAngle &&
            (normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY) <=
            config.standingMaximumHipDropRatio

    private fun normalizedHipDrop(sample: PoseFeatureSample): Double? {
        if (standingLegLength <= EPSILON || state == SquatState.CALIBRATING) return null
        return (sample.hipY - standingHipY) / standingLegLength
    }

    private fun beginCycleIfNeeded(sample: PoseFeatureSample, hipDrop: Double) {
        if (cycleStartedMs != null) return
        cycleStartedMs = sample.timestampMs
        minimumKnee = sample.kneeAngleDeg
        maximumHipDrop = hipDrop
        bottomReached = false
    }

    private fun recordAttempt(sample: PoseFeatureSample, hipDrop: Double) {
        minimumKnee = min(minimumKnee, sample.kneeAngleDeg)
        maximumHipDrop = max(maximumHipDrop, hipDrop)
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
        calibrationStatus = CALIBRATION_TIMED_OUT
        lastResetReason = RESET_CALIBRATION_TIMEOUT
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
                standingCandidateSinceMs = null
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
        lastTransitionReason = RESET_TO_CALIBRATING
        lastResetReason = reason
        resetCalibration()
        clearCycle(clearAttemptMetrics = false)
        previousKnee = null
        previousHipY = null
    }

    private fun resetCalibration() {
        calibrationStartedMs = null
        calibrationSide = null
        calibrationHipYs.clear()
        calibrationLegLengths.clear()
        calibrationKnees.clear()
        calibrationStatus = WAITING_FOR_STANDING
    }

    private fun clearCycle(clearAttemptMetrics: Boolean) {
        cycleStartedMs = null
        descendingCandidateSinceMs = null
        bottomCandidateSinceMs = null
        ascendingCandidateSinceMs = null
        standingCandidateSinceMs = null
        bottomReached = false
        if (clearAttemptMetrics) {
            minimumKnee = 180.0
            maximumHipDrop = 0.0
        }
    }

    private fun diagnostics(
        quality: PoseQualityMetrics,
        filteredKnee: Double?,
        rawKnee: Double?,
        hipDrop: Double?,
        kneeVelocity: Double?,
        hipVelocity: Double?,
        timestampMs: Long,
    ): SquatFrameDiagnostics {
        val calibrated = calibrationStatus == CALIBRATION_COMPLETE || state != SquatState.CALIBRATING
        val thresholds = thresholds()
        return SquatFrameDiagnostics(
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
                if (bottomReached) candidateDuration(standingCandidateSinceMs, timestampMs) else 0,
            currentRepDurationMs = cycleStartedMs?.let { (timestampMs - it).coerceAtLeast(0) },
            calibratedStandingKneeAngleDeg = standingKneeAngle.takeIf { calibrated },
            standingThresholdDeg = thresholds.standingEnterAngle,
            descendingThresholdDeg = thresholds.descendingStartAngle,
            bottomThresholdDeg = thresholds.bottomAngle,
            returnStandingThresholdDeg = thresholds.returnStandingAngle,
            minimumAttemptKneeAngleDeg = minimumKnee.takeIf { cycleStartedMs != null || it < 180.0 },
            maximumAttemptHipDropRatio = maximumHipDrop.takeIf { cycleStartedMs != null || it > 0.0 },
            baselineHipY = standingHipY.takeIf { calibrated },
            legScale = standingLegLength.takeIf { calibrated },
            baselineJitter = baselineJitter.takeIf { calibrated },
            calibrationSelectedSide = calibrationSide.takeIf { calibrated },
        )
    }

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

    private fun emptyDiagnostics(): SquatFrameDiagnostics {
        val thresholds = config.thresholdsFor(180.0)
        return SquatFrameDiagnostics(
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
            calibrationStatus = WAITING_FOR_STANDING,
            bottomReached = false,
            standingConfirmationDurationMs = 0,
            bottomConfirmationDurationMs = 0,
            returnStandingDurationMs = 0,
            currentRepDurationMs = null,
            calibratedStandingKneeAngleDeg = null,
            standingThresholdDeg = thresholds.standingEnterAngle,
            descendingThresholdDeg = thresholds.descendingStartAngle,
            bottomThresholdDeg = thresholds.bottomAngle,
            returnStandingThresholdDeg = thresholds.returnStandingAngle,
            minimumAttemptKneeAngleDeg = null,
            maximumAttemptHipDropRatio = null,
            baselineHipY = null,
            legScale = null,
            baselineJitter = null,
            calibrationSelectedSide = null,
        )
    }

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

        const val WAITING_FOR_STANDING = "WAITING_FOR_STANDING"
        const val WAITING_FOR_DESCENT = "WAITING_FOR_DESCENT"
        const val WAITING_FOR_ASCENT = "WAITING_FOR_ASCENT"
        const val WAITING_FOR_REFRACTORY = "WAITING_FOR_REFRACTORY"
        const val DESCENDING_BY_ANGLE = "DESCENDING_BY_ANGLE"
        const val DESCENDING_BY_HIP_DROP = "DESCENDING_BY_HIP_DROP"
        const val BOTTOM_ANGLE_NOT_REACHED = "BOTTOM_ANGLE_NOT_REACHED"
        const val BOTTOM_HIP_DROP_NOT_REACHED = "BOTTOM_HIP_DROP_NOT_REACHED"
        const val BOTTOM_CONFIRMING = "BOTTOM_CONFIRMING"
        const val BOTTOM_CONFIRMED = "BOTTOM_CONFIRMED"
        const val BOTTOM_CONFIRMED_DIRECT = "BOTTOM_CONFIRMED_DIRECT_FROM_STANDING"
        const val ASCENDING_CONFIRMED = "ASCENDING_CONFIRMED"
        const val RETURNED_TO_BOTTOM = "RETURNED_TO_BOTTOM"
        const val RETURN_ANGLE_NOT_REACHED = "RETURN_ANGLE_NOT_REACHED"
        const val RETURN_HIP_DROP_NOT_REACHED = "RETURN_HIP_DROP_NOT_REACHED"
        const val RETURN_STANDING_CONFIRMING = "RETURN_STANDING_CONFIRMING"
        const val REP_ACCEPTED = "REP_ACCEPTED"
        const val REJECT_SHALLOW = "REJECT_SHALLOW"
        const val REJECT_DURATION = "REJECT_DURATION"
        const val REJECT_DUPLICATE = "REJECT_DUPLICATE"
        const val REJECT_DUPLICATE_TIMESTAMP = "REJECT_DUPLICATE_TIMESTAMP"
        const val REJECT_POSE_LOST = "REJECT_POSE_LOST"
        const val REJECT_CALIBRATION_MOTION = "REJECT_CALIBRATION_MOTION"
        const val RESET_POSE_LOST = "RESET_POSE_LOST"
        const val RESET_REP_TIMEOUT = "RESET_REP_TIMEOUT"
        const val RESET_SESSION = "RESET_SESSION"
        const val RESET_CALIBRATION_SIDE_CHANGED = "RESET_CALIBRATION_SIDE_CHANGED"
        const val RESET_CALIBRATION_TIMEOUT = "RESET_CALIBRATION_TIMEOUT"
        const val RESET_TO_CALIBRATING = "RESET_TO_CALIBRATING"
        const val CALIBRATION_COLLECTING = "COLLECTING"
        const val CALIBRATION_COMPLETE = "COMPLETE"
        const val CALIBRATION_UNSTABLE = "UNSTABLE"
        const val CALIBRATION_TIMED_OUT = "TIMED_OUT"
    }
}
