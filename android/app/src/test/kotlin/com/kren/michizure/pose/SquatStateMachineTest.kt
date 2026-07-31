package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun standingAngle168ProducesBottomThreshold133() {
        val thresholds = config.thresholdsFor(168.0)

        assertEquals(156.0, thresholds.standingEnterAngle, 0.001)
        assertEquals(148.0, thresholds.descendingStartAngle, 0.001)
        assertEquals(133.0, thresholds.bottomAngle, 0.001)
        assertEquals(153.0, thresholds.returnStandingAngle, 0.001)
    }

    @Test
    fun standingAngle175KeepsBottomThresholdInsideClamp() {
        val bottom = config.thresholdsFor(175.0).bottomAngle

        assertEquals(140.0, bottom, 0.001)
        assertTrue(bottom in 125.0..140.0)
    }

    @Test
    fun lowStandingAngleCannotProduceBottomThresholdBelow125() {
        val bottom = config.thresholdsFor(150.0).bottomAngle

        assertEquals(125.0, bottom, 0.001)
    }

    @Test
    fun calibrationUsesEightNonContiguousSamplesAndExposesBaseline() {
        val detector = calibratedDetector()
        val diagnostics = detector.valid(CALIBRATED_AT + 10, 168.0, 0.25).diagnostics

        assertEquals(SquatState.STANDING, detector.state)
        assertEquals("COMPLETE", diagnostics.calibrationStatus)
        assertEquals(168.0, diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
        assertEquals(0.25, diagnostics.baselineHipY!!, 0.001)
        assertEquals(0.50, diagnostics.legScale!!, 0.001)
        assertEquals(PoseSide.LEFT, diagnostics.calibrationSelectedSide)
    }

    @Test
    fun normalSquatProducesExactlyOneRepAfterReturnToStanding() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, CALIBRATED_AT + 200)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
        assertEquals("REP_ACCEPTED", updates.last().diagnostics.lastTransitionReason)
    }

    @Test
    fun irregularFiveFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 150.0, 0.285),
                detector.valid(start + 220, 145.0, 0.290),
                detector.valid(start + 430, 133.0, 0.305),
                detector.valid(start + 650, 132.0, 0.305),
                detector.valid(start + 880, 140.0, 0.290),
                detector.valid(start + 1_100, 150.0, 0.280),
                detector.valid(start + 1_330, 154.0, 0.270),
                detector.valid(start + 1_560, 160.0, 0.260),
            )

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun irregularEightFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = mutableListOf<SquatDetectorUpdate>()
        listOf(
            Triple(0L, 150.0, 0.285),
            Triple(130L, 146.0, 0.290),
            Triple(270L, 138.0, 0.295),
            Triple(410L, 133.0, 0.305),
            Triple(570L, 132.0, 0.305),
            Triple(710L, 138.0, 0.295),
            Triple(850L, 145.0, 0.290),
            Triple(1_020L, 151.0, 0.280),
            Triple(1_240L, 154.0, 0.270),
            Triple(1_470L, 160.0, 0.260),
        ).forEach { (offset, knee, hip) -> updates += detector.valid(start + offset, knee, hip) }

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun standingCanSkipDescendingAndObserveBottomDirectly() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200

        detector.valid(start, 132.0, 0.305)
        val bottom = detector.valid(start + 150, 131.0, 0.305)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(bottom.diagnostics.bottomReached)
        assertEquals("BOTTOM_CONFIRMED_DIRECT_FROM_STANDING", bottom.diagnostics.lastTransitionReason)
        assertEquals(1, directReturnToStanding(detector, start + 800).count { it.repCompleted })
    }

    @Test
    fun bottomCanSkipAscendingAndReturnDirectlyToStanding() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val updates = directReturnToStanding(detector, start + 1_000)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun tenNormalSquatsProduceExactlyTenMonotonicReps() {
        val detector = calibratedDetector()
        val sequences = mutableListOf<Int>()
        var start = CALIBRATED_AT + 200
        repeat(10) {
            sequences += normalRep(detector, start)
                .filter { it.repCompleted }
                .map { it.repSequence }
            start += 2_200
        }

        assertEquals((1..10).toList(), sequences)
        assertEquals(10, detector.repSequence)
    }

    @Test
    fun tenShallowSquatsNeverCount() {
        val detector = calibratedDetector()
        var start = CALIBRATED_AT + 200
        repeat(10) {
            shallowRep(detector, start)
            start += 1_400
        }

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun deepSquatIsAcceptedInsteadOfRejected() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += detector.valid(start, 146.0, 0.285)
        updates += detector.valid(start + 150, 140.0, 0.290)
        updates += detector.valid(start + 350, 105.0, 0.285)
        updates += detector.valid(start + 500, 100.0, 0.285)
        updates += detector.valid(start + 750, 140.0, 0.290)
        updates += detector.valid(start + 950, 151.0, 0.280)
        updates += detector.valid(start + 1_150, 154.0, 0.270)
        updates += detector.valid(start + 1_400, 160.0, 0.260)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun forwardBendHipDropWithoutKneeFlexionNeverCounts() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        listOf(
            detector.valid(start, 168.0, 0.285),
            detector.valid(start + 200, 166.0, 0.310),
            detector.valid(start + 450, 168.0, 0.315),
            detector.valid(start + 700, 165.0, 0.270),
            detector.valid(start + 1_000, 165.0, 0.260),
        )

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun incompleteDescentDoesNotCount() {
        val detector = calibratedDetector()

        shallowRep(detector, CALIBRATED_AT + 200)

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun missingReturnToStandingDoesNotCount() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)
        detector.valid(start + 800, 140.0, 0.290)
        detector.valid(start + 1_000, 149.0, 0.280)
        detector.valid(start + 1_300, 151.0, 0.275)

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun bottomBounceCannotCreateDuplicateRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = descendToBottom(detector, start).toMutableList()
        updates += detector.valid(start + 800, 140.0, 0.290)
        updates += detector.valid(start + 950, 146.0, 0.285)
        updates += detector.valid(start + 1_100, 132.0, 0.305)
        updates += detector.valid(start + 1_300, 130.0, 0.310)
        updates += detector.valid(start + 1_500, 142.0, 0.290)
        updates += detector.valid(start + 1_650, 150.0, 0.280)
        updates += detector.valid(start + 1_850, 154.0, 0.270)
        updates += detector.valid(start + 2_100, 160.0, 0.260)
        updates += detector.valid(start + 2_200, 160.0, 0.260)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun sevenHundredMillisecondFrameGapKeepsPhaseAndBottomReached() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)
        assertEquals(SquatState.BOTTOM, detector.state)

        val afterGap = detector.valid(start + 1_250, 140.0, 0.290)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(afterGap.diagnostics.bottomReached)
        assertNull(afterGap.diagnostics.kneeAngularVelocity)
        assertEquals(700L, afterGap.diagnostics.frameDtMs)
        assertFalse(afterGap.diagnostics.lastResetReason == "RESET_FRAME_GAP")
    }

    @Test
    fun fourteenHundredMillisecondPoseLossDoesNotReset() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val update = detector.invalid(start + 1_950)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(update.diagnostics.bottomReached)
    }

    @Test
    fun poseLossLongerThanFifteenHundredMillisecondsResetsAttempt() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val reset = detector.invalid(start + 2_051)

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertFalse(reset.diagnostics.bottomReached)
        assertEquals("RESET_POSE_LOST", reset.diagnostics.lastResetReason)
    }

    @Test
    fun duplicateAndOutOfOrderTimestampsAreRejected() {
        val detector = calibratedDetector()
        val time = CALIBRATED_AT + 200
        detector.valid(time, 146.0, 0.285)

        val duplicate = detector.valid(time, 100.0, 0.320)
        val reversed = detector.valid(time - 1, 100.0, 0.320)

        assertEquals("REJECT_DUPLICATE_TIMESTAMP", duplicate.diagnostics.latestRejectReason)
        assertEquals("REJECT_DUPLICATE_TIMESTAMP", reversed.diagnostics.latestRejectReason)
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun minimumAndMaximumRepDurationAreEnforced() {
        val fast = calibratedDetector()
        val fastStart = CALIBRATED_AT + 200
        fast.valid(fastStart, 132.0, 0.305)
        fast.valid(fastStart + 125, 131.0, 0.305)
        fast.valid(fastStart + 350, 154.0, 0.270)
        val fastRejected = fast.valid(fastStart + 560, 160.0, 0.260)
        assertEquals(0, fast.repSequence)
        assertEquals("REJECT_DURATION", fastRejected.diagnostics.latestRejectReason)

        val slow = calibratedDetector()
        val slowStart = CALIBRATED_AT + 200
        descendToBottom(slow, slowStart)
        val slowRejected = slow.valid(slowStart + 6_100, 140.0, 0.290)
        assertEquals(SquatState.CALIBRATING, slow.state)
        assertEquals("RESET_REP_TIMEOUT", slowRejected.diagnostics.lastResetReason)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        CALIBRATION_TIMES.forEach { time -> detector.valid(time, 168.0, 0.25) }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun normalRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = descendToBottom(detector, start).toMutableList()
        updates += detector.valid(start + 800, 140.0, 0.290)
        updates += detector.valid(start + 950, 148.0, 0.285)
        updates += detector.valid(start + 1_150, 154.0, 0.270)
        updates += detector.valid(start + 1_400, 160.0, 0.260)
        return updates
    }

    private fun descendToBottom(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 150.0, 0.285),
        detector.valid(start + 150, 145.0, 0.290),
        detector.valid(start + 350, 133.0, 0.305),
        detector.valid(start + 550, 132.0, 0.305),
    )

    private fun directReturnToStanding(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 154.0, 0.270),
        detector.valid(start + 220, 160.0, 0.260),
    )

    private fun shallowRep(
        detector: SquatStateMachine,
        start: Long,
    ) {
        detector.valid(start, 150.0, 0.285)
        detector.valid(start + 150, 145.0, 0.290)
        detector.valid(start + 350, 140.0, 0.295)
        detector.valid(start + 600, 158.0, 0.270)
        detector.valid(start + 850, 160.0, 0.260)
    }

    private fun SquatStateMachine.valid(
        timestampMs: Long,
        knee: Double,
        hipY: Double,
        side: PoseSide = PoseSide.LEFT,
    ) = process(
        PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = timestampMs,
                    kneeAngleDeg = knee,
                    rawKneeAngleDeg = knee,
                    hipY = hipY,
                    legLength = 0.50,
                    confidence = 0.90,
                    selectedSide = side,
                ),
            quality =
                PoseQualityMetrics.EMPTY.copy(
                    poseDetected = true,
                    selectedSide = side,
                    trackingStatus = PoseTrackingStatus.VALID,
                ),
        ),
    )

    private fun SquatStateMachine.invalid(timestampMs: Long) =
        process(
            PoseFeatureResult.Invalid(
                timestampMs = timestampMs,
                warning = PoseQualityWarning.NO_POSE_DETECTED,
                quality = PoseQualityMetrics.EMPTY.copy(trackingStatus = PoseTrackingStatus.NO_POSE),
                rejectReason = "poseNotDetected",
            ),
        )

    private companion object {
        val CALIBRATION_TIMES = listOf(0L, 300L, 600L, 900L, 1_200L, 1_500L, 1_800L, 2_100L)
        const val CALIBRATED_AT = 2_100L
    }
}
