package com.kren.michizure.pose

import java.util.ArrayDeque
import kotlin.math.max

class SquatStateMachine(
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    var state: SquatState = SquatState.CALIBRATING
        private set

    var repSequence: Int = 0
        private set

    private val samples = ArrayDeque<PoseFeatureSample>()
    private var filteredKnee: Double? = null
    private var filteredHip: Double? = null
    private var filteredHipY: Double? = null
    private var filteredLegLength: Double? = null
    private var previousTimestampMs: Long? = null
    private var previousKnee: Double? = null
    private var invalidSinceMs: Long? = null
    private var calibrationStartedMs: Long? = null
    private val calibrationHipYs = mutableListOf<Double>()
    private val calibrationLegLengths = mutableListOf<Double>()
    private var standingHipY = 0.0
    private var standingLegLength = 1.0
    private var cycleStartedMs: Long? = null
    private var stateEnteredMs: Long? = null
    private var bottomCandidateSinceMs: Long? = null
    private var standingCandidateSinceMs: Long? = null
    private var lastRepAtMs: Long = Long.MIN_VALUE
    private var minimumKnee = 180.0
    private var maximumKnee = 0.0
    private var cycleFrames = 0
    private var validCycleFrames = 0

    fun process(result: PoseFeatureResult): SquatDetectorUpdate {
        return when (result) {
            is PoseFeatureResult.Invalid -> processInvalid(result)
            is PoseFeatureResult.Valid -> processValid(result.sample)
        }
    }

    fun reset() {
        state = SquatState.CALIBRATING
        samples.clear()
        filteredKnee = null
        filteredHip = null
        filteredHipY = null
        filteredLegLength = null
        previousTimestampMs = null
        previousKnee = null
        invalidSinceMs = null
        resetCalibration()
        clearCycle()
    }

    private fun processInvalid(result: PoseFeatureResult.Invalid): SquatDetectorUpdate {
        if (cycleStartedMs != null) cycleFrames += 1
        val started = invalidSinceMs ?: result.timestampMs.also { invalidSinceMs = it }
        previousKnee = null
        previousTimestampMs = null
        if (result.timestampMs - started > config.invalidTrackingGraceMs) {
            resetToCalibrating()
        }
        return update(warning = result.warning)
    }

    private fun processValid(raw: PoseFeatureSample): SquatDetectorUpdate {
        val lastTimestamp = previousTimestampMs
        if (lastTimestamp != null && raw.timestampMs <= lastTimestamp) {
            return update()
        }
        if (lastTimestamp != null &&
            raw.timestampMs - lastTimestamp > config.maximumFrameGapMs
        ) {
            resetToCalibrating()
        }
        invalidSinceMs = null
        val sample = smooth(raw)
        val priorKnee = previousKnee
        val priorTimestamp = previousTimestampMs
        val velocity =
            if (priorKnee == null || priorTimestamp == null) {
                0.0
            } else {
                (sample.kneeAngleDeg - priorKnee) /
                    ((sample.timestampMs - priorTimestamp) / 1_000.0)
            }
        previousKnee = sample.kneeAngleDeg
        previousTimestampMs = sample.timestampMs

        if (cycleStartedMs != null) {
            cycleFrames += 1
            validCycleFrames += 1
            minimumKnee = minOf(minimumKnee, sample.kneeAngleDeg)
            maximumKnee = maxOf(maximumKnee, sample.kneeAngleDeg)
        }

        return when (state) {
            SquatState.CALIBRATING -> calibrate(sample)
            SquatState.STANDING -> fromStanding(sample, velocity)
            SquatState.DESCENDING -> fromDescending(sample, velocity)
            SquatState.BOTTOM -> fromBottom(sample, velocity)
            SquatState.ASCENDING -> fromAscending(sample, velocity)
        }
    }

    private fun calibrate(sample: PoseFeatureSample): SquatDetectorUpdate {
        if (!isStanding(sample)) {
            resetCalibration()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        val started = calibrationStartedMs ?: sample.timestampMs.also {
            calibrationStartedMs = it
        }
        calibrationHipYs += sample.hipY
        calibrationLegLengths += sample.legLength
        val legMedian = median(calibrationLegLengths)
        val hipDrift =
            (calibrationHipYs.maxOrNull()!! - calibrationHipYs.minOrNull()!!) /
                legMedian
        if (hipDrift > config.calibrationMaximumHipDriftRatio) {
            resetCalibration()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.timestampMs - started >= config.calibrationStableMs) {
            standingHipY = median(calibrationHipYs)
            standingLegLength = legMedian
            transition(SquatState.STANDING, sample.timestampMs)
            return update()
        }
        return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
    }

    private fun fromStanding(
        sample: PoseFeatureSample,
        velocity: Double,
    ): SquatDetectorUpdate {
        if (elapsedSinceLastRep(sample.timestampMs) < config.refractoryMs) return update()
        if (sample.kneeAngleDeg < config.descendingKneeDeg &&
            velocity < -config.minimumMovementVelocityDegPerSec
        ) {
            cycleStartedMs = sample.timestampMs
            cycleFrames = 1
            validCycleFrames = 1
            minimumKnee = sample.kneeAngleDeg
            maximumKnee = sample.kneeAngleDeg
            transition(SquatState.DESCENDING, sample.timestampMs)
        }
        return update()
    }

    private fun fromDescending(
        sample: PoseFeatureSample,
        velocity: Double,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (isStanding(sample)) {
            transition(SquatState.STANDING, sample.timestampMs)
            clearCycle()
            return update()
        }
        val deepEnough =
            sample.kneeAngleDeg <= config.bottomKneeDeg &&
                sample.hipAngleDeg <= config.bottomHipDeg &&
                hipDrop(sample) >= config.bottomHipDropRatio
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
        velocity: Double,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
            resetToCalibrating()
            return update(PoseQualityWarning.HOLD_STILL_TO_CALIBRATE)
        }
        if (sample.kneeAngleDeg >= config.bottomExitKneeDeg &&
            velocity > config.minimumMovementVelocityDegPerSec
        ) {
            transition(SquatState.ASCENDING, sample.timestampMs)
        }
        return update()
    }

    private fun fromAscending(
        sample: PoseFeatureSample,
        velocity: Double,
    ): SquatDetectorUpdate {
        if (cycleTimedOut(sample.timestampMs)) {
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
        if (!validRep) return update()
        lastRepAtMs = sample.timestampMs
        repSequence += 1
        return update(repCompleted = true)
    }

    private fun smooth(raw: PoseFeatureSample): PoseFeatureSample {
        samples.addLast(raw)
        while (samples.size > config.medianWindowSize) samples.removeFirst()
        val medianKnee = median(samples.map { it.kneeAngleDeg })
        val medianHip = median(samples.map { it.hipAngleDeg })
        val medianHipY = median(samples.map { it.hipY })
        val medianLeg = median(samples.map { it.legLength })
        filteredKnee = ema(filteredKnee, medianKnee)
        filteredHip = ema(filteredHip, medianHip)
        filteredHipY = ema(filteredHipY, medianHipY)
        filteredLegLength = ema(filteredLegLength, medianLeg)
        return raw.copy(
            kneeAngleDeg = requireNotNull(filteredKnee),
            hipAngleDeg = requireNotNull(filteredHip),
            hipY = requireNotNull(filteredHipY),
            legLength = requireNotNull(filteredLegLength),
        )
    }

    private fun ema(previous: Double?, current: Double): Double =
        previous?.let { config.emaAlpha * current + (1 - config.emaAlpha) * it } ?: current

    private fun isStanding(sample: PoseFeatureSample): Boolean =
        sample.kneeAngleDeg >= config.standingKneeDeg &&
            sample.hipAngleDeg >= config.standingHipDeg

    private fun hipDrop(sample: PoseFeatureSample): Double =
        (sample.hipY - standingHipY) / max(standingLegLength, 1e-6)

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

    private fun resetToCalibrating() {
        state = SquatState.CALIBRATING
        stateEnteredMs = null
        resetCalibration()
        clearCycle()
        samples.clear()
        filteredKnee = null
        filteredHip = null
        filteredHipY = null
        filteredLegLength = null
        previousKnee = null
        previousTimestampMs = null
    }

    private fun resetCalibration() {
        calibrationStartedMs = null
        calibrationHipYs.clear()
        calibrationLegLengths.clear()
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

    private fun update(
        warning: PoseQualityWarning? = null,
        repCompleted: Boolean = false,
    ) = SquatDetectorUpdate(
        state = state,
        qualityWarning = warning,
        repCompleted = repCompleted,
        repSequence = repSequence,
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
