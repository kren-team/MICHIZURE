package com.kren.michizure.pose

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Timestamp-driven detector that accumulates knee, hip, and reversal evidence
 * over an attempt. A delayed valid frame invalidates velocity only; a sustained
 * pose loss is the only frame-timing condition that discards the attempt.
 */
class SquatStateMachine(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
    isEmulator: Boolean = false,
) {
    private val poseLossResetMs = config.poseLossResetMs(isEmulator)
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
    private var standingCandidateSinceMs: Long? = null
    private var lastRepAtMs = Long.MIN_VALUE
    private var minimumKnee = 180.0
    private var maximumHipDrop = 0.0
    private var lastAttemptKnee: Double? = null
    private var lastAttemptHipDrop: Double? = null
    private var downwardMovementObserved = false
    private var upwardMovementObserved = false
    private var bottomEvidenceScore = 0
    private var bottomEvidencePath: BottomEvidencePath? = null
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
        if (lastValid != null && result.timestampMs - lastValid > poseLossResetMs) {
            rejectActiveCycle(REJECT_POSE_LOST)
            resetToCalibrating(RESET_POSE_LOSS_TIMEOUT)
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
        var validGapMs = lastValidTimestampMs?.let { sample.timestampMs - it }
        if (validGapMs != null && validGapMs > poseLossResetMs) {
            rejectActiveCycle(REJECT_POSE_LOST)
            resetToCalibrating(RESET_POSE_LOSS_TIMEOUT)
            validGapMs = null
        }
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
        if (cycleStartedMs != null) observeAttempt(sample, hipDrop ?: 0.0)

        val detectorUpdate =
            when (state) {
                SquatState.CALIBRATING -> calibrate(sample)
                SquatState.STANDING -> fromStanding(sample)
                SquatState.DESCENDING -> fromDescending(sample)
                SquatState.BOTTOM -> fromBottom(sample, kneeVelocity, hipVelocity)
                SquatState.ASCENDING -> fromAscending(sample, kneeVelocity, hipVelocity)
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
        val descendingByAngle = sample.kneeAngleDeg < thresholds().descendingStartAngle
        val descendingByHipDrop = hipDrop > config.descendingHipDropRatio
        val minimumMovement =
            standingKneeAngle - sample.kneeAngleDeg >=
                config.hipReversalMinimumKneeBendDeltaDeg ||
                hipDrop >= config.mediumHipDropRatio
        if (!descendingByAngle && !descendingByHipDrop && !minimumMovement) {
            latestRejectReason = WAITING_FOR_DESCENT
            return update()
        }

        beginCycle(sample, hipDrop)
        currentBottomEvidence().path?.let { path ->
            return confirmBottom(sample, path)
        }
        transition(
            SquatState.DESCENDING,
            sample.timestampMs,
            if (descendingByAngle) DESCENDING_BY_ANGLE else DESCENDING_BY_HIP_DROP,
        )
        latestRejectReason = REJECT_NO_BOTTOM_EVIDENCE
        return update()
    }

    private fun fromDescending(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        currentBottomEvidence().path?.let { path ->
            confirmBottom(sample, path)
            if (upwardMovementObserved && isReturnStanding(sample)) {
                return confirmReturnStanding(sample)
            }
            return update(currentDepthWarning(sample))
        }
        if (isReturnStanding(sample)) return confirmRejectedReturn(sample)

        standingCandidateSinceMs = null
        latestRejectReason = REJECT_NO_BOTTOM_EVIDENCE
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

        val movingUp =
            upwardMovementObserved ||
                (kneeVelocity != null && kneeVelocity > 0.0) ||
                (hipVelocity != null && hipVelocity < 0.0)
        if (movingUp) {
            transition(SquatState.ASCENDING, sample.timestampMs, ASCENDING_CONFIRMED)
            latestRejectReason = WAITING_FOR_RETURN
        } else {
            latestRejectReason = bottomEvidencePath?.transitionReason ?: BOTTOM_CONFIRMED
        }
        return update(currentDepthWarning(sample))
    }

    private fun fromAscending(
        sample: PoseFeatureSample,
        kneeVelocity: Double?,
        hipVelocity: Double?,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) return timeout()
        if (isReturnStanding(sample)) return confirmReturnStanding(sample)

        val movingDown =
            (kneeVelocity != null && kneeVelocity < 0.0) ||
                (hipVelocity != null && hipVelocity > 0.0)
        if (movingDown && currentBottomEvidence().path != null) {
            transition(SquatState.BOTTOM, sample.timestampMs, RETURNED_TO_BOTTOM)
        }
        standingCandidateSinceMs = null
        latestRejectReason = WAITING_FOR_RETURN
        return update(currentDepthWarning(sample))
    }

    private fun confirmBottom(
        sample: PoseFeatureSample,
        path: BottomEvidencePath,
    ): SquatDetectorUpdate {
        bottomReached = true
        bottomEvidencePath = path
        transition(SquatState.BOTTOM, sample.timestampMs, path.transitionReason)
        latestRejectReason = null
        return update(currentDepthWarning(sample))
    }

    private fun confirmRejectedReturn(sample: PoseFeatureSample): SquatDetectorUpdate {
        val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
            standingCandidateSinceMs = it
        }
        val strongSingleSample = isStrongReturnStanding(sample)
        if (!strongSingleSample && sample.timestampMs - candidate < config.returnStandingConfirmationMs) {
            latestRejectReason = REJECT_NO_BOTTOM_EVIDENCE
            return update()
        }
        rejectActiveCycle(REJECT_SHALLOW)
        transition(SquatState.STANDING, sample.timestampMs, REJECT_SHALLOW)
        clearCycle(clearAttemptMetrics = false)
        return update()
    }

    private fun confirmReturnStanding(sample: PoseFeatureSample): SquatDetectorUpdate {
        val candidate = standingCandidateSinceMs ?: sample.timestampMs.also {
            standingCandidateSinceMs = it
        }
        val strongSingleSample = isStrongReturnStanding(sample)
        if (!strongSingleSample && sample.timestampMs - candidate < config.returnStandingConfirmationMs) {
            latestRejectReason = WAITING_FOR_RETURN
            return update()
        }

        val totalDuration = sample.timestampMs - requireNotNull(cycleStartedMs)
        val durationValid = totalDuration in config.minimumRepDurationMs..config.maximumRepDurationMs
        val refractoryComplete = elapsedSinceLastRep(sample.timestampMs) >= config.refractoryMs
        val validRep = bottomReached && durationValid && refractoryComplete

        if (!validRep) {
            val reason =
                when {
                    !bottomReached -> REJECT_NO_BOTTOM_EVIDENCE
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

    private fun beginCycle(sample: PoseFeatureSample, hipDrop: Double) {
        cycleStartedMs = sample.timestampMs
        minimumKnee = sample.kneeAngleDeg
        maximumHipDrop = hipDrop
        lastAttemptKnee = sample.kneeAngleDeg
        lastAttemptHipDrop = hipDrop
        downwardMovementObserved =
            standingKneeAngle - sample.kneeAngleDeg >= config.initialDownwardKneeDeltaDeg ||
            hipDrop >= config.initialDownwardHipDropRatio
        upwardMovementObserved = false
        bottomReached = false
        bottomEvidencePath = null
        bottomEvidenceScore = currentBottomEvidence().score
    }

    private fun observeAttempt(sample: PoseFeatureSample, hipDrop: Double) {
        val priorKnee = lastAttemptKnee
        val priorHipDrop = lastAttemptHipDrop
        if (priorKnee != null && priorHipDrop != null) {
            if (sample.kneeAngleDeg <= priorKnee - config.movementKneeDeltaDeg ||
                hipDrop >= priorHipDrop + config.movementHipDropDeltaRatio
            ) {
                downwardMovementObserved = true
            }
            if (downwardMovementObserved &&
                (sample.kneeAngleDeg >= minimumKnee + config.movementKneeDeltaDeg ||
                    hipDrop <= maximumHipDrop - config.movementHipDropDeltaRatio)
            ) {
                upwardMovementObserved = true
            }
        }
        minimumKnee = min(minimumKnee, sample.kneeAngleDeg)
        maximumHipDrop = max(maximumHipDrop, hipDrop)
        lastAttemptKnee = sample.kneeAngleDeg
        lastAttemptHipDrop = hipDrop
        val evidence = currentBottomEvidence()
        bottomEvidenceScore = evidence.score
        if (bottomEvidencePath == null) bottomEvidencePath = evidence.path
    }

    private fun currentBottomEvidence(): BottomEvidence =
        config.bottomEvidence(
            calibratedStandingAngle = standingKneeAngle,
            minimumKneeAngle = minimumKnee,
            maximumHipDrop = maximumHipDrop,
            downwardMovementObserved = downwardMovementObserved,
            upwardMovementObserved = upwardMovementObserved,
        ).also { bottomEvidenceScore = it.score }

    private fun currentDepthWarning(sample: PoseFeatureSample): PoseQualityWarning? {
        val hipDrop = normalizedHipDrop(sample) ?: 0.0
        return if (sample.kneeAngleDeg <= config.tooDeepKneeDeg &&
            hipDrop >= config.tooDeepHipDropRatio
        ) {
            PoseQualityWarning.TOO_DEEP
        } else {
            null
        }
    }

    private fun isStrongReturnStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >= thresholds().returnStandingAngle

    private fun isReturnStanding(sample: PoseFeatureSample): Boolean {
        val hipDrop = normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY
        val thresholds = thresholds()
        return sample.kneeAngleDeg >= thresholds.returnStandingAngle ||
            (sample.kneeAngleDeg >= thresholds.returnStandingRelaxedAngle &&
                hipDrop <= config.returnStandingMaximumHipDropRatio &&
                upwardMovementObserved)
    }

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
        lastTransitionReason = reason
        standingCandidateSinceMs = null
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
        lastTransitionReason = RESET_TO_CALIBRATING
        lastResetReason = reason
        resetCalibration()
        clearCycle(clearAttemptMetrics = true)
        lastValidTimestampMs = null
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
        standingCandidateSinceMs = null
        lastAttemptKnee = null
        lastAttemptHipDrop = null
        bottomReached = false
        if (clearAttemptMetrics) {
            minimumKnee = 180.0
            maximumHipDrop = 0.0
            downwardMovementObserved = false
            upwardMovementObserved = false
            bottomEvidencePath = null
            bottomEvidenceScore = 0
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
            standingConfirmationDurationMs = 0,
            bottomConfirmationDurationMs = 0,
            returnStandingDurationMs = candidateDuration(standingCandidateSinceMs, timestampMs),
            currentRepDurationMs = cycleStartedMs?.let { (timestampMs - it).coerceAtLeast(0) },
            calibratedStandingKneeAngleDeg = standingKneeAngle.takeIf { calibrated },
            standingThresholdDeg = thresholds.standingEnterAngle,
            descendingThresholdDeg = thresholds.descendingStartAngle,
            bottomThresholdDeg = thresholds.bottomAngle,
            returnStandingThresholdDeg = thresholds.returnStandingAngle,
            minimumAttemptKneeAngleDeg = minimumKnee.takeIf { cycleStartedMs != null || it < 180.0 },
            maximumAttemptHipDropRatio = maximumHipDrop.takeIf { cycleStartedMs != null || it > 0.0 },
            kneeBendDeltaDeg =
                (standingKneeAngle - minimumKnee).coerceAtLeast(0.0)
                    .takeIf { cycleStartedMs != null || minimumKnee < 180.0 },
            downwardMovementObserved = downwardMovementObserved,
            upwardMovementObserved = upwardMovementObserved,
            bottomEvidenceScore = bottomEvidenceScore,
            bottomEvidencePath = bottomEvidencePath,
            attemptStartTimestampMs = cycleStartedMs,
            lastValidPoseTimestampMs = lastValidTimestampMs,
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
            kneeBendDeltaDeg = null,
            downwardMovementObserved = false,
            upwardMovementObserved = false,
            bottomEvidenceScore = 0,
            bottomEvidencePath = null,
            attemptStartTimestampMs = null,
            lastValidPoseTimestampMs = null,
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
        const val WAITING_FOR_RETURN = "WAITING_FOR_RETURN"
        const val WAITING_FOR_REFRACTORY = "WAITING_FOR_REFRACTORY"
        const val DESCENDING_BY_ANGLE = "DESCENDING_BY_ANGLE"
        const val DESCENDING_BY_HIP_DROP = "DESCENDING_BY_HIP_DROP"
        const val BOTTOM_CONFIRMED = "BOTTOM_CONFIRMED"
        const val ASCENDING_CONFIRMED = "ASCENDING_CONFIRMED"
        const val RETURNED_TO_BOTTOM = "RETURNED_TO_BOTTOM"
        const val REP_ACCEPTED = "REP_ACCEPTED"
        const val REJECT_SHALLOW = "REJECT_SHALLOW"
        const val REJECT_NO_BOTTOM_EVIDENCE = "REJECT_NO_BOTTOM_EVIDENCE"
        const val REJECT_DURATION = "REJECT_DURATION"
        const val REJECT_DUPLICATE = "REJECT_DUPLICATE"
        const val REJECT_DUPLICATE_TIMESTAMP = "REJECT_DUPLICATE_TIMESTAMP"
        const val REJECT_POSE_LOST = "REJECT_POSE_LOST"
        const val REJECT_CALIBRATION_MOTION = "REJECT_CALIBRATION_MOTION"
        const val RESET_POSE_LOSS_TIMEOUT = "RESET_POSE_LOSS_TIMEOUT"
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
