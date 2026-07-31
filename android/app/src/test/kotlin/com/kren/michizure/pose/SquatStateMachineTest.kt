package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun calibrationUsesNonContiguousStableSamplesAndRobustBaseline() {
        val detector = SquatStateMachine(config)
        listOf(0L, 250L, 700L, 1_100L, 1_450L, 2_050L).forEachIndexed { index, time ->
            detector.valid(time, 168.0 + (index % 2), 0.250 + (index % 2) * 0.001)
        }

        assertEquals(SquatState.STANDING, detector.state)
        assertEquals("complete", detector.valid(2_100, 169.0, 0.25).diagnostics.calibrationStatus)
    }

    @Test
    fun normalSquatProducesExactlyOneRepAfterReturnToStanding() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, CALIBRATED_AT + 200)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun irregularFiveFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 146.0, 0.29),
                detector.valid(start + 220, 140.0, 0.31),
                detector.valid(start + 430, 118.0, 0.36),
                detector.valid(start + 650, 108.0, 0.38),
                detector.valid(start + 880, 128.0, 0.34),
                detector.valid(start + 1_100, 140.0, 0.32),
                detector.valid(start + 1_330, 152.0, 0.315),
                detector.valid(start + 1_560, 160.0, 0.30),
            )

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun irregularEightFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = mutableListOf<SquatDetectorUpdate>()
        listOf(
            Triple(0L, 147.0, 0.29),
            Triple(130L, 143.0, 0.30),
            Triple(270L, 130.0, 0.33),
            Triple(410L, 117.0, 0.36),
            Triple(570L, 108.0, 0.38),
            Triple(710L, 126.0, 0.35),
            Triple(850L, 138.0, 0.33),
            Triple(1_020L, 151.0, 0.32),
            Triple(1_240L, 160.0, 0.30),
        ).forEach { (offset, knee, hip) -> updates += detector.valid(start + offset, knee, hip) }

        assertEquals(1, updates.count { it.repCompleted })
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
            detector.valid(start + 1_900, 165.0, 0.30)
            start += 2_100
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
            start += 1_500
        }
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun deepSquatIsAcceptedInsteadOfRejected() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 145.0, 0.30),
                detector.valid(start + 150, 135.0, 0.32),
                detector.valid(start + 350, 50.0, 0.41),
                detector.valid(start + 550, 45.0, 0.42),
                detector.valid(start + 750, 128.0, 0.35),
                detector.valid(start + 900, 140.0, 0.33),
                detector.valid(start + 1_100, 152.0, 0.32),
                detector.valid(start + 1_350, 160.0, 0.30),
            )

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun forwardBendHipDropWithoutKneeFlexionNeverCounts() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        listOf(
            detector.valid(start, 168.0, 0.31),
            detector.valid(start + 200, 166.0, 0.38),
            detector.valid(start + 450, 168.0, 0.39),
            detector.valid(start + 700, 165.0, 0.30),
            detector.valid(start + 1_000, 165.0, 0.30),
        )

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun incompleteDescentAndIncompleteAscentDoNotCount() {
        val descent = calibratedDetector()
        shallowRep(descent, CALIBRATED_AT + 200)
        assertEquals(0, descent.repSequence)

        val ascent = calibratedDetector()
        val start = CALIBRATED_AT + 200
        normalDescent(ascent, start)
        ascent.valid(start + 800, 130.0, 0.35)
        ascent.valid(start + 1_000, 140.0, 0.33)
        ascent.valid(start + 1_300, 145.0, 0.325)
        assertEquals(0, ascent.repSequence)
    }

    @Test
    fun bottomBounceCannotCreateDuplicateRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = normalDescent(detector, start).toMutableList()
        updates += detector.valid(start + 800, 130.0, 0.35)
        updates += detector.valid(start + 950, 140.0, 0.33)
        updates += detector.valid(start + 1_100, 112.0, 0.37)
        updates += detector.valid(start + 1_300, 105.0, 0.38)
        updates += detector.valid(start + 1_500, 130.0, 0.35)
        updates += detector.valid(start + 1_650, 140.0, 0.33)
        updates += detector.valid(start + 1_850, 152.0, 0.32)
        updates += detector.valid(start + 2_100, 160.0, 0.30)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun sevenHundredMillisecondFrameGapKeepsCurrentPhaseAndResetsVelocityOnly() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        detector.valid(start, 145.0, 0.30)
        detector.valid(start + 150, 140.0, 0.31)
        assertEquals(SquatState.DESCENDING, detector.state)

        val afterGap = detector.valid(start + 850, 118.0, 0.36)

        assertEquals(SquatState.DESCENDING, detector.state)
        assertNull(afterGap.diagnostics.kneeAngularVelocity)
        assertEquals(700L, afterGap.diagnostics.frameDtMs)
        assertFalse(afterGap.diagnostics.lastResetReason == "frameGap")
    }

    @Test
    fun fourteenHundredMillisecondPoseLossDoesNotResetButLongerLossDoes() {
        val short = calibratedDetector()
        val shortStart = CALIBRATED_AT + 200
        short.valid(shortStart, 145.0, 0.30)
        short.valid(shortStart + 150, 140.0, 0.31)
        short.invalid(shortStart + 1_550)
        assertEquals(SquatState.DESCENDING, short.state)

        val long = calibratedDetector()
        val longStart = CALIBRATED_AT + 200
        long.valid(longStart, 145.0, 0.30)
        long.valid(longStart + 150, 140.0, 0.31)
        val reset = long.invalid(longStart + 1_651)
        assertEquals(SquatState.CALIBRATING, long.state)
        assertEquals("poseLoss", reset.diagnostics.lastResetReason)
    }

    @Test
    fun duplicateAndOutOfOrderTimestampsAreRejected() {
        val detector = calibratedDetector()
        val time = CALIBRATED_AT + 200
        detector.valid(time, 145.0, 0.30)

        val duplicate = detector.valid(time, 100.0, 0.38)
        val reversed = detector.valid(time - 1, 100.0, 0.38)

        assertEquals("duplicateFrame", duplicate.diagnostics.latestRejectReason)
        assertEquals("duplicateFrame", reversed.diagnostics.latestRejectReason)
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun returnToStandingRequiresMonotonicTimeConfirmation() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        normalDescent(detector, start)
        detector.valid(start + 800, 130.0, 0.35)
        detector.valid(start + 950, 140.0, 0.33)
        detector.valid(start + 1_150, 152.0, 0.32)
        val tooEarly = detector.valid(start + 1_300, 160.0, 0.30)
        assertFalse(tooEarly.repCompleted)

        val confirmed = detector.valid(start + 1_370, 160.0, 0.30)
        assertTrue(confirmed.repCompleted)
    }

    @Test
    fun detectorRecoversAfterVelocityResetGapAndCompletesRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        detector.valid(start, 145.0, 0.30)
        detector.valid(start + 150, 140.0, 0.31)
        detector.valid(start + 850, 118.0, 0.36)
        detector.valid(start + 1_050, 108.0, 0.38)
        detector.valid(start + 1_750, 130.0, 0.35)
        detector.valid(start + 1_900, 140.0, 0.33)
        detector.valid(start + 2_100, 152.0, 0.32)
        val accepted = detector.valid(start + 2_350, 160.0, 0.30)

        assertTrue(accepted.repCompleted)
        assertEquals(1, detector.repSequence)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        CALIBRATION_TIMES.forEachIndexed { index, time ->
            detector.valid(time, 168.0 + (index % 2), 0.25 + (index % 2) * 0.001)
        }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun normalRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = normalDescent(detector, start).toMutableList()
        updates += detector.valid(start + 800, 130.0, 0.35)
        updates += detector.valid(start + 950, 140.0, 0.33)
        updates += detector.valid(start + 1_150, 152.0, 0.32)
        updates += detector.valid(start + 1_400, 160.0, 0.30)
        return updates
    }

    private fun normalDescent(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 145.0, 0.30),
        detector.valid(start + 150, 140.0, 0.31),
        detector.valid(start + 350, 118.0, 0.36),
        detector.valid(start + 550, 108.0, 0.38),
    )

    private fun shallowRep(
        detector: SquatStateMachine,
        start: Long,
    ) {
        detector.valid(start, 146.0, 0.29)
        detector.valid(start + 150, 142.0, 0.30)
        detector.valid(start + 350, 130.0, 0.32)
        detector.valid(start + 550, 158.0, 0.30)
        detector.valid(start + 850, 165.0, 0.30)
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
