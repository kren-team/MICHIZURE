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
    private val returnPoseWaitMs = config.returnPoseWaitMs(isEmulator)
    private val calibrationTimeoutMs = config.calibrationTimeoutMs(isEmulator)
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
    private var pendingSide: PoseSide? = null
    private var pendingSideSamples = 0
    private var sideMissingSinceMs: Long? = null
    private val calibrationCandidates = ArrayDeque<StandingCandidate>()
    private var calibrationStatus = WAITING_FOR_STANDING
    private var provisionalStandingCandidate: StandingCandidate? = null
    private var calibrationQualityPath: CalibrationQualityPath? = null
    private var lastCalibrationRejectReason: String? = null
    private var candidateBufferPreserved = false
    private var autoCalibratedOnDescent = false
    private var standingBaselineSource: String? = null
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
    private var clearCycleAfterDiagnostics = false

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
            is PoseFeatureResult.CalibrationCandidate -> processCalibrationCandidate(result)
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
        clearCycleAfterDiagnostics = false
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
        if (state == SquatState.CALIBRATING) {
            if (calibrationStartedMs == null) calibrationStartedMs = result.timestampMs
            lastCalibrationRejectReason = result.rejectReason
            candidateBufferPreserved = hasCalibrationCandidate()
        }
        val lastValid = lastValidTimestampMs
        if (lastValid != null && result.timestampMs - lastValid > activePoseLossTimeoutMs()) {
            rejectActiveCycle(REJECT_POSE_LOST)
            resetToCalibrating(RESET_POSE_LOSS_TIMEOUT)
        } else if (state == SquatState.CALIBRATING) {
            expireCalibrationIfNeeded(result.timestampMs)
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
        return processUsableSample(
            sample = result.sample,
            quality = result.quality,
            qualityPath = CalibrationQualityPath.NORMAL,
        )
    }

    private fun processCalibrationCandidate(
        result: PoseFeatureResult.CalibrationCandidate,
    ): SquatDetectorUpdate {
        if (state != SquatState.CALIBRATING) {
            return processInvalid(
                PoseFeatureResult.Invalid(
                    timestampMs = result.timestampMs,
                    warning = result.warning,
                    quality = result.quality,
                    rejectReason = result.rejectReason,
                ),
            )
        }
        return processUsableSample(
            sample = result.sample,
            quality = result.quality,
            qualityPath = result.qualityPath,
        )
    }

    private fun processUsableSample(
        sample: PoseFeatureSample,
        quality: PoseQualityMetrics,
        qualityPath: CalibrationQualityPath,
    ): SquatDetectorUpdate {
        if (!acceptSelectedSide(sample)) {
            lastValidTimestampMs = sample.timestampMs
            previousKnee = null
            previousHipY = null
            recordValidPoseTime(sample.timestampMs)
            latestRejectReason = REJECT_CALIBRATION_SIDE_CHANGED
            if (state == SquatState.CALIBRATING) {
                lastCalibrationRejectReason = REJECT_CALIBRATION_SIDE_CHANGED
                candidateBufferPreserved = hasCalibrationCandidate()
            }
            lastDiagnostics =
                diagnostics(
                    quality = quality,
                    filteredKnee = sample.kneeAngleDeg,
                    rawKnee = sample.rawKneeAngleDeg,
                    hipDrop = null,
                    kneeVelocity = null,
                    hipVelocity = null,
                    timestampMs = sample.timestampMs,
                )
            return update().copy(diagnostics = lastDiagnostics)
        }
        var validGapMs = lastValidTimestampMs?.let { sample.timestampMs - it }
        if (validGapMs != null && validGapMs > activePoseLossTimeoutMs()) {
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
                SquatState.CALIBRATING -> calibrate(sample, qualityPath)
                SquatState.STANDING -> fromStanding(sample)
                SquatState.DESCENDING -> fromDescending(sample)
                SquatState.BOTTOM -> fromBottom(sample, kneeVelocity, hipVelocity)
                SquatState.ASCENDING -> fromAscending(sample, kneeVelocity, hipVelocity)
            }
        lastDiagnostics =
            diagnostics(
                quality = quality,
                filteredKnee = sample.kneeAngleDeg,
                rawKnee = sample.rawKneeAngleDeg,
                hipDrop = normalizedHipDrop(sample),
                kneeVelocity = kneeVelocity,
                hipVelocity = hipVelocity,
                timestampMs = sample.timestampMs,
            )
        val completed = detectorUpdate.copy(diagnostics = lastDiagnostics)
        if (clearCycleAfterDiagnostics) {
            clearCycle(clearAttemptMetrics = true)
            clearCycleAfterDiagnostics = false
        }
        return completed
    }

    private fun calibrate(
        sample: PoseFeatureSample,
        qualityPath: CalibrationQualityPath,
    ): SquatDetectorUpdate {
        if (calibrationStartedMs == null) calibrationStartedMs = sample.timestampMs
        pruneCalibrationWindow(sample.timestampMs)
        val provisional = provisionalStandingCandidate?.sample?.kneeAngleDeg
        if (provisional != null &&
            provisional - sample.kneeAngleDeg >= config.calibrationAutoDescentDeltaDeg
        ) {
            finalizeCalibration(AUTO_CALIBRATED_ON_DESCENT)
            autoCalibratedOnDescent = true
            val hipDrop = ((sample.hipY - standingHipY) / standingLegLength).coerceAtLeast(0.0)
            beginCycle(sample, hipDrop)
            currentBottomEvidence().path?.let { path ->
                return confirmBottom(sample, path)
            }
            transition(SquatState.DESCENDING, sample.timestampMs, AUTO_CALIBRATED_ON_DESCENT)
            latestRejectReason = REJECT_NO_BOTTOM_EVIDENCE
            return update()
        }

        if (calibrationSide != null && calibrationSide != sample.selectedSide) {
            calibrationStatus = CALIBRATION_COLLECTING
            lastCalibrationRejectReason = REJECT_CALIBRATION_SIDE_CHANGED
            candidateBufferPreserved = hasCalibrationCandidate()
            expireCalibrationIfNeeded(sample.timestampMs)
            latestRejectReason = REJECT_CALIBRATION_SIDE_CHANGED
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        calibrationSide = sample.selectedSide
        if (sample.kneeAngleDeg < config.calibrationAuxiliaryStandingMinimumKneeDeg) {
            calibrationStatus = WAITING_FOR_STANDING
            expireCalibrationIfNeeded(sample.timestampMs)
            latestRejectReason = WAITING_FOR_STANDING
            lastCalibrationRejectReason = WAITING_FOR_STANDING
            candidateBufferPreserved = hasCalibrationCandidate()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }

        if (isCalibrationMotionOutlier(sample)) {
            calibrationStatus = CALIBRATION_UNSTABLE
            latestRejectReason = REJECT_CALIBRATION_MOTION
            lastCalibrationRejectReason = REJECT_CALIBRATION_MOTION
            candidateBufferPreserved = hasCalibrationCandidate()
            expireCalibrationIfNeeded(sample.timestampMs)
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }

        addCalibrationSample(sample, qualityPath)
        calibrationStatus = CALIBRATION_COLLECTING
        calibrationQualityPath = qualityPath
        candidateBufferPreserved = false
        lastCalibrationRejectReason = null
        if (sample.kneeAngleDeg >= config.calibrationProvisionalStandingMinimumKneeDeg) {
            val candidate = calibrationCandidates.last()
            if ((provisionalStandingCandidate?.sample?.kneeAngleDeg ?: Double.NEGATIVE_INFINITY) <
                sample.kneeAngleDeg
            ) {
                provisionalStandingCandidate = candidate
            }
        }

        val enoughSamples = calibrationCandidates.size >= config.calibrationMinimumSamples
        val angleRange = calibrationAngleRange()
        if (enoughSamples &&
            angleRange != null &&
            angleRange <= config.calibrationMaximumAngleRangeDeg
        ) {
            val source =
                if (calibrationCandidates.size == config.calibrationMinimumSamples) {
                    TWO_SAMPLE_MEDIAN
                } else {
                    MULTI_SAMPLE_MEDIAN
                }
            finalizeCalibration(source)
            transition(
                SquatState.STANDING,
                sample.timestampMs,
                if (source == TWO_SAMPLE_MEDIAN) {
                    CALIBRATED_FROM_TWO_SAMPLES
                } else {
                    CALIBRATED_FROM_MULTI_SAMPLES
                },
            )
            return update()
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

        autoCalibratedOnDescent = false
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
        clearCycleAfterDiagnostics = true
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
            clearCycleAfterDiagnostics = true
            return update()
        }

        lastRepAtMs = sample.timestampMs
        repSequence += 1
        latestRejectReason = null
        transition(SquatState.STANDING, sample.timestampMs, REP_ACCEPTED)
        clearCycleAfterDiagnostics = true
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

    private fun isStrongReturnStanding(sample: PoseFeatureSample): Boolean {
        val hipDrop = normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY
        return hipDrop <= config.returnStandingMaximumHipDropRatio &&
            (sample.kneeAngleDeg >= thresholds().returnStandingAngle ||
                (sample.kneeAngleDeg >= config.returnStandingAbsoluteKneeDeg &&
                    sample.kneeAngleDeg - minimumKnee >= config.returnStandingMinimumRecoveryDeg))
    }

    private fun isReturnStanding(sample: PoseFeatureSample): Boolean {
        val hipDrop = normalizedHipDrop(sample) ?: Double.POSITIVE_INFINITY
        val thresholds = thresholds()
        return isStrongReturnStanding(sample) ||
            (sample.kneeAngleDeg >= thresholds.returnStandingRelaxedAngle &&
                hipDrop <= config.returnStandingMaximumHipDropRatio &&
                upwardMovementObserved)
    }

    private fun normalizedHipDrop(sample: PoseFeatureSample): Double? {
        if (standingLegLength <= EPSILON || state == SquatState.CALIBRATING) return null
        return (sample.hipY - standingHipY) / standingLegLength
    }

    private fun addCalibrationSample(
        sample: PoseFeatureSample,
        qualityPath: CalibrationQualityPath,
    ) {
        calibrationCandidates.addLast(
            StandingCandidate(
                sample = sample,
                qualityPath = qualityPath,
            ),
        )
        while (calibrationCandidates.size > config.calibrationTargetSamples) {
            calibrationCandidates.removeFirst()
        }
    }

    private fun acceptSelectedSide(sample: PoseFeatureSample): Boolean {
        val selected = calibrationSide
        if (selected == null) {
            calibrationSide = sample.selectedSide
            clearPendingSide()
            return true
        }
        if (selected == sample.selectedSide) {
            clearPendingSide()
            return true
        }
        if (pendingSide != sample.selectedSide) {
            pendingSide = sample.selectedSide
            pendingSideSamples = 1
            sideMissingSinceMs = sample.timestampMs
        } else {
            pendingSideSamples += 1
        }
        val missingSince = sideMissingSinceMs ?: sample.timestampMs
        if (pendingSideSamples < config.sideChangeConfirmationSamples ||
            sample.timestampMs - missingSince < config.sideMissingGraceMs
        ) {
            return false
        }
        calibrationSide = sample.selectedSide
        clearPendingSide()
        return true
    }

    private fun clearPendingSide() {
        pendingSide = null
        pendingSideSamples = 0
        sideMissingSinceMs = null
    }

    private fun activePoseLossTimeoutMs(): Long =
        when {
            bottomReached -> returnPoseWaitMs
            sideMissingSinceMs != null -> max(poseLossResetMs, config.sideMissingGraceMs)
            else -> poseLossResetMs
        }

    private fun pruneCalibrationWindow(timestampMs: Long) {
        while (calibrationCandidates.isNotEmpty() &&
            timestampMs - calibrationCandidates.first().sample.timestampMs >
            config.calibrationWindowMs
        ) {
            calibrationCandidates.removeFirst()
            candidateBufferPreserved = true
        }
    }

    private fun isCalibrationMotionOutlier(sample: PoseFeatureSample): Boolean {
        if (sample.kneeAngleDeg >= config.calibrationStrongStandingMinimumKneeDeg) return false
        val center = calibrationMedianAngle() ?: return false
        val hipCenter = median(calibrationCandidates.map { it.sample.hipY })
        val legCenter = median(calibrationCandidates.map { it.sample.legLength })
        val hipDrift = abs(sample.hipY - hipCenter) / max(legCenter, EPSILON)
        return abs(sample.kneeAngleDeg - center) > config.calibrationMaximumAngleRangeDeg ||
            hipDrift > config.calibrationMaximumHipDriftRatio
    }

    private fun finalizeCalibration(source: String) {
        val sourceCandidates =
            calibrationCandidates.ifEmpty {
                listOfNotNull(provisionalStandingCandidate)
            }
        val selected =
            sourceCandidates
                .sortedByDescending { it.sample.kneeAngleDeg }
                .take(config.calibrationPreferredSamples.coerceAtMost(sourceCandidates.size))
        check(selected.isNotEmpty())
        val hips = selected.map { it.sample.hipY }
        val legs = selected.map { it.sample.legLength }
        val knees = selected.map { it.sample.kneeAngleDeg }
        standingHipY = median(hips)
        standingLegLength = median(legs)
        standingKneeAngle = median(knees)
        val hipJitter = robustSpread(hips) / max(standingLegLength, EPSILON)
        val kneeJitter = robustSpread(knees)
        baselineJitter = max(hipJitter, kneeJitter / 180.0)
        calibrationQualityPath =
            selected.firstOrNull { it.qualityPath != CalibrationQualityPath.NORMAL }?.qualityPath
                ?: CalibrationQualityPath.NORMAL
        calibrationStatus = CALIBRATION_COMPLETE
        standingBaselineSource = source
        provisionalStandingCandidate = selected.first()
        latestRejectReason = null
        lastCalibrationRejectReason = null
    }

    private fun calibrationMedianAngle(): Double? =
        calibrationCandidates
            .map { it.sample.kneeAngleDeg }
            .takeIf { it.isNotEmpty() }
            ?.let(::median)

    private fun hasCalibrationCandidate(): Boolean =
        calibrationCandidates.isNotEmpty() || provisionalStandingCandidate != null

    private fun calibrationAngleRange(): Double? {
        if (calibrationCandidates.isEmpty()) return null
        val knees = calibrationCandidates.map { it.sample.kneeAngleDeg }
        return knees.max() - knees.min()
    }

    private fun expireCalibrationIfNeeded(timestampMs: Long) {
        val started = calibrationStartedMs ?: return
        if (timestampMs - started <= calibrationTimeoutMs) return
        val strongCandidate =
            calibrationCandidates.any {
                it.sample.kneeAngleDeg >= config.calibrationStrongStandingMinimumKneeDeg
            } ||
                (provisionalStandingCandidate?.sample?.kneeAngleDeg ?: 0.0) >=
                config.calibrationStrongStandingMinimumKneeDeg
        when {
            strongCandidate -> {
                finalizeCalibration(TIMEOUT_PROVISIONAL)
                calibrationStatus = CALIBRATION_COMPLETE
                candidateBufferPreserved = true
                lastResetReason = CALIBRATION_TIMEOUT_USED_PROVISIONAL
                transition(
                    SquatState.STANDING,
                    timestampMs,
                    CALIBRATION_TIMEOUT_USED_PROVISIONAL,
                )
            }
            calibrationCandidates.isNotEmpty() || provisionalStandingCandidate != null -> {
                calibrationStartedMs = timestampMs
                calibrationStatus = CALIBRATION_EXTENDED
                candidateBufferPreserved = true
                lastResetReason = CALIBRATION_TIMEOUT_EXTENDED
            }
            else -> {
                resetCalibration()
                calibrationStatus = CALIBRATION_TIMED_OUT
                lastResetReason = CALIBRATION_TIMEOUT_NO_CANDIDATE
            }
        }
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
        clearPendingSide()
        calibrationCandidates.clear()
        calibrationStatus = WAITING_FOR_STANDING
        provisionalStandingCandidate = null
        calibrationQualityPath = null
        lastCalibrationRejectReason = null
        candidateBufferPreserved = false
        autoCalibratedOnDescent = false
        standingBaselineSource = null
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
        val calibrated = standingBaselineSource != null || state != SquatState.CALIBRATING
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
            calibrationSampleCount = calibrationCandidates.size,
            calibrationStatus = calibrationStatus,
            strongStandingCandidateCount =
                calibrationCandidates.count {
                    it.sample.kneeAngleDeg >= config.calibrationStrongStandingMinimumKneeDeg
                },
            provisionalStandingAngleDeg = provisionalStandingCandidate?.sample?.kneeAngleDeg,
            calibrationMedianAngleDeg = calibrationMedianAngle(),
            calibrationAngleRangeDeg = calibrationAngleRange(),
            calibrationWindowAgeMs =
                calibrationCandidates.firstOrNull()?.sample?.timestampMs?.let {
                    (timestampMs - it).coerceAtLeast(0)
                },
            calibrationTimeoutMs = calibrationTimeoutMs,
            calibrationQualityPath = calibrationQualityPath,
            lastCalibrationRejectReason = lastCalibrationRejectReason,
            candidateBufferPreserved = candidateBufferPreserved,
            autoCalibratedOnDescent = autoCalibratedOnDescent,
            standingBaselineSource = standingBaselineSource,
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
            strongStandingCandidateCount = 0,
            provisionalStandingAngleDeg = null,
            calibrationMedianAngleDeg = null,
            calibrationAngleRangeDeg = null,
            calibrationWindowAgeMs = null,
            calibrationTimeoutMs = calibrationTimeoutMs,
            calibrationQualityPath = null,
            lastCalibrationRejectReason = null,
            candidateBufferPreserved = false,
            autoCalibratedOnDescent = false,
            standingBaselineSource = null,
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

    private data class StandingCandidate(
        val sample: PoseFeatureSample,
        val qualityPath: CalibrationQualityPath,
    )

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
        const val REJECT_CALIBRATION_SIDE_CHANGED = "REJECT_CALIBRATION_SIDE_CHANGED"
        const val RESET_POSE_LOSS_TIMEOUT = "RESET_POSE_LOSS_TIMEOUT"
        const val RESET_REP_TIMEOUT = "RESET_REP_TIMEOUT"
        const val RESET_SESSION = "RESET_SESSION"
        const val RESET_TO_CALIBRATING = "RESET_TO_CALIBRATING"
        const val CALIBRATION_COLLECTING = "COLLECTING"
        const val CALIBRATION_COMPLETE = "COMPLETE"
        const val CALIBRATION_UNSTABLE = "UNSTABLE"
        const val CALIBRATION_TIMED_OUT = "TIMED_OUT"
        const val CALIBRATION_EXTENDED = "EXTENDED"
        const val CALIBRATED_FROM_TWO_SAMPLES = "CALIBRATED_FROM_TWO_SAMPLES"
        const val CALIBRATED_FROM_MULTI_SAMPLES = "CALIBRATED_FROM_MULTI_SAMPLES"
        const val AUTO_CALIBRATED_ON_DESCENT = "AUTO_CALIBRATED_ON_DESCENT"
        const val CALIBRATION_TIMEOUT_NO_CANDIDATE = "CALIBRATION_TIMEOUT_NO_CANDIDATE"
        const val CALIBRATION_TIMEOUT_USED_PROVISIONAL =
            "CALIBRATION_TIMEOUT_USED_PROVISIONAL"
        const val CALIBRATION_TIMEOUT_EXTENDED = "CALIBRATION_TIMEOUT_EXTENDED"
        const val MULTI_SAMPLE_MEDIAN = "MULTI_SAMPLE_MEDIAN"
        const val TWO_SAMPLE_MEDIAN = "TWO_SAMPLE_MEDIAN"
        const val TIMEOUT_PROVISIONAL = "TIMEOUT_PROVISIONAL"
    }
}
