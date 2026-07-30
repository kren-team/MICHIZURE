package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun validLowerBodyCycleProducesExactlyOneRep() {
        val detector = calibratedDetector()

        val updates = validRep(detector, 1_100)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun tenNormalSquatsProduceExactlyTenReps() {
        val detector = calibratedDetector()
        val updates = mutableListOf<SquatDetectorUpdate>()
        var start = 1_100L
        repeat(10) {
            updates += validRep(detector, start)
            val finalStanding = start + 1_150
            detector.valid(finalStanding + 250, 170.0, 0.25)
            start = finalStanding + 500
        }

        assertEquals(10, updates.count { it.repCompleted })
        assertEquals(10, detector.repSequence)
    }

    @Test
    fun standingShallowAndIncompleteMotionsDoNotCount() {
        val detector = calibratedDetector()
        val updates = listOf(
            detector.valid(1_100, 170.0, 0.25),
            detector.valid(1_200, 145.0, 0.29),
            detector.valid(1_400, 130.0, 0.31),
            detector.valid(1_700, 165.0, 0.25),
            detector.valid(2_000, 170.0, 0.25),
        )

        assertFalse(updates.any { it.repCompleted })
        assertEquals(0, detector.repSequence)
        assertTrue(detector.rejectedAttempts >= 1)
    }

    @Test
    fun standingJitterAndSmallKneeBendAreRejected() {
        val detector = calibratedDetector()
        val updates = listOf(
            detector.valid(1_100, 165.0, 0.252),
            detector.valid(1_200, 158.0, 0.255),
            detector.valid(1_300, 162.0, 0.251),
            detector.valid(1_400, 155.0, 0.256),
            detector.valid(1_600, 170.0, 0.25),
        )

        assertFalse(updates.any { it.repCompleted })
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun bottomBounceDoesNotDoubleCount() {
        val detector = calibratedDetector()
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += descentToBottom(detector, 1_100)
        updates += detector.valid(1_500, 120.0, 0.38)
        updates += detector.valid(1_600, 100.0, 0.40)
        updates += detector.valid(1_700, 120.0, 0.36)
        updates += finishStanding(detector, 1_800)

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun shortPoseLossFreezesButLongLossResetsCycle() {
        val shortLoss = calibratedDetector()
        val shortUpdates = mutableListOf<SquatDetectorUpdate>()
        shortUpdates += descentToBottom(shortLoss, 1_100)
        shortUpdates += shortLoss.invalid(1_550)
        shortUpdates += shortLoss.invalid(1_700)
        shortUpdates += finishStanding(shortLoss, 1_800)
        assertEquals(1, shortUpdates.count { it.repCompleted })

        val longLoss = calibratedDetector()
        val longUpdates = mutableListOf<SquatDetectorUpdate>()
        longUpdates += descentToBottom(longLoss, 1_100)
        longUpdates += longLoss.invalid(1_550)
        longUpdates += longLoss.invalid(1_900)
        longUpdates += finishStanding(longLoss, 2_000)
        assertFalse(longUpdates.any { it.repCompleted })
        assertEquals(SquatState.CALIBRATING, longLoss.state)
    }

    @Test
    fun duplicateAndOutOfOrderFramesCannotCreateExtraRep() {
        val detector = calibratedDetector()
        val updates = validRep(detector, 1_100).toMutableList()
        updates += detector.valid(2_250, 170.0, 0.25)
        updates += detector.valid(2_000, 90.0, 0.40)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals("duplicateFrame", updates.last().diagnostics.latestRejectReason)
    }

    @Test
    fun thresholdOscillationAndStartingAtBottomDoNotCount() {
        val jitter = calibratedDetector()
        val jitterUpdates = listOf(
            jitter.valid(1_100, 151.0, 0.26),
            jitter.valid(1_200, 149.0, 0.27),
            jitter.valid(1_300, 151.0, 0.26),
            jitter.valid(1_400, 148.0, 0.27),
            jitter.valid(1_600, 165.0, 0.25),
        )
        assertFalse(jitterUpdates.any { it.repCompleted })

        val bottomStart = SquatStateMachine(config)
        repeat(15) { index ->
            bottomStart.valid(index * 100L, 95.0, 0.40)
        }
        assertEquals(SquatState.CALIBRATING, bottomStart.state)
        assertEquals(0, bottomStart.repSequence)
    }

    @Test
    fun tooFastAndTooSlowCyclesDoNotCount() {
        val fast = calibratedDetector()
        val fastUpdates = listOf(
            fast.valid(1_100, 145.0, 0.30),
            fast.valid(1_200, 100.0, 0.40),
            fast.valid(1_300, 100.0, 0.40),
            fast.valid(1_400, 125.0, 0.35),
            fast.valid(1_500, 165.0, 0.25),
            fast.valid(1_600, 170.0, 0.25),
        )
        assertFalse(fastUpdates.any { it.repCompleted })

        val slow = calibratedDetector()
        val slowUpdates = descentToBottom(slow, 1_100).toMutableList()
        slowUpdates += slow.valid(7_500, 120.0, 0.35)
        slowUpdates += finishStanding(slow, 7_600)
        assertFalse(slowUpdates.any { it.repCompleted })
    }

    @Test
    fun invalidLowerBodyConfidenceNeverAdvancesCalibration() {
        val detector = SquatStateMachine(config)
        repeat(20) { index -> detector.invalid(index * 100L) }

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertEquals(0, detector.repSequence)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        repeat(11) { index ->
            detector.valid(index * 100L, 170.0, 0.25)
        }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun validRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = descentToBottom(detector, start).toMutableList()
        updates += finishStanding(detector, start + 500)
        return updates
    }

    private fun descentToBottom(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 145.0, 0.30),
        detector.valid(start + 100, 125.0, 0.34),
        detector.valid(start + 200, 100.0, 0.40),
        detector.valid(start + 300, 100.0, 0.40),
    )

    private fun finishStanding(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 120.0, 0.36),
        detector.valid(start + 200, 150.0, 0.30),
        detector.valid(start + 400, 165.0, 0.25),
        detector.valid(start + 650, 170.0, 0.25),
    )

    private fun SquatStateMachine.valid(
        timestampMs: Long,
        knee: Double,
        hipY: Double,
    ) = process(
        PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = timestampMs,
                    kneeAngleDeg = knee,
                    hipY = hipY,
                    legLength = 0.50,
                    confidence = 0.90,
                    selectedSide = PoseSide.LEFT,
                ),
            quality =
                PoseQualityMetrics.EMPTY.copy(
                    poseDetected = true,
                    selectedSide = PoseSide.LEFT,
                ),
        ),
    )

    private fun SquatStateMachine.invalid(timestampMs: Long) =
        process(
            PoseFeatureResult.Invalid(
                timestampMs,
                PoseQualityWarning.SHOW_LOWER_BODY,
                rejectReason = "lowerBodyConfidenceLow",
            ),
        )
}
