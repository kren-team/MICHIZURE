package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config =
        SquatDetectorConfig(
            medianWindowSize = 1,
            emaAlpha = 1.0,
        )

    @Test
    fun validCycleProducesExactlyOneRep() {
        val detector = calibratedDetector()

        val updates = validRep(detector, 1_100)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun twoCyclesProduceExactlyTwoReps() {
        val detector = calibratedDetector()

        val first = validRep(detector, 1_100)
        detector.valid(2_500, 170.0, 160.0, 0.25)
        val second = validRep(detector, 2_750)

        assertEquals(2, (first + second).count { it.repCompleted })
        assertEquals(2, detector.repSequence)
    }

    @Test
    fun standingShallowAndIncompleteMotionsDoNotCount() {
        val detector = calibratedDetector()
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += detector.valid(1_100, 170.0, 165.0, 0.25)
        updates += detector.valid(1_200, 145.0, 140.0, 0.30)
        updates += detector.valid(1_400, 130.0, 130.0, 0.32)
        updates += detector.valid(1_700, 165.0, 155.0, 0.25)
        updates += detector.valid(2_000, 170.0, 160.0, 0.25)

        assertFalse(updates.any { it.repCompleted })
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun bottomBounceDoesNotDoubleCount() {
        val detector = calibratedDetector()
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += descentToBottom(detector, 1_100)
        updates += detector.valid(1_500, 120.0, 115.0, 0.39)
        updates += detector.valid(1_600, 100.0, 105.0, 0.40)
        updates += detector.valid(1_700, 120.0, 120.0, 0.37)
        updates += finishStanding(detector, 1_800)

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun shortPoseLossFreezesButLongLossResetsCycle() {
        val shortLoss = calibratedDetector()
        val shortUpdates = mutableListOf<SquatDetectorUpdate>()
        shortUpdates += descentToBottom(shortLoss, 1_100)
        shortUpdates += shortLoss.invalid(1_650)
        shortUpdates += shortLoss.invalid(1_800)
        shortUpdates += finishStanding(shortLoss, 1_900)
        assertEquals(1, shortUpdates.count { it.repCompleted })

        val longLoss = calibratedDetector()
        val longUpdates = mutableListOf<SquatDetectorUpdate>()
        longUpdates += descentToBottom(longLoss, 1_100)
        longUpdates += longLoss.invalid(1_650)
        longUpdates += longLoss.invalid(1_950)
        longUpdates += finishStanding(longLoss, 2_000)
        assertFalse(longUpdates.any { it.repCompleted })
        assertEquals(SquatState.CALIBRATING, longLoss.state)
    }

    @Test
    fun duplicateAndOutOfOrderFramesCannotCreateExtraRep() {
        val detector = calibratedDetector()
        val updates = validRep(detector, 1_100).toMutableList()
        updates += detector.valid(2_100, 170.0, 160.0, 0.25)
        updates += detector.valid(2_000, 90.0, 90.0, 0.40)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun thresholdJitterAndStartAtBottomDoNotCount() {
        val jitter = calibratedDetector()
        val jitterUpdates =
            listOf(
                jitter.valid(1_100, 151.0, 145.0, 0.26),
                jitter.valid(1_200, 149.0, 144.0, 0.27),
                jitter.valid(1_300, 151.0, 145.0, 0.26),
                jitter.valid(1_400, 148.0, 143.0, 0.27),
                jitter.valid(1_600, 165.0, 155.0, 0.25),
            )
        assertFalse(jitterUpdates.any { it.repCompleted })

        val bottomStart = SquatStateMachine(config)
        repeat(15) { index ->
            bottomStart.valid(index * 100L, 95.0, 100.0, 0.40)
        }
        assertEquals(SquatState.CALIBRATING, bottomStart.state)
        assertEquals(0, bottomStart.repSequence)
    }

    @Test
    fun tooFastAndTooSlowCyclesDoNotCount() {
        val fast = calibratedDetector()
        val fastUpdates =
            listOf(
                fast.valid(1_100, 145.0, 140.0, 0.30),
                fast.valid(1_200, 100.0, 105.0, 0.40),
                fast.valid(1_300, 100.0, 105.0, 0.40),
                fast.valid(1_400, 125.0, 125.0, 0.35),
                fast.valid(1_500, 165.0, 155.0, 0.25),
                fast.valid(1_600, 170.0, 160.0, 0.25),
            )
        assertFalse(fastUpdates.any { it.repCompleted })

        val slow = calibratedDetector()
        val slowUpdates = descentToBottom(slow, 1_100).toMutableList()
        slowUpdates += slow.valid(7_500, 120.0, 120.0, 0.35)
        slowUpdates += finishStanding(slow, 7_600)
        assertFalse(slowUpdates.any { it.repCompleted })
    }

    @Test
    fun confidenceFailureNeverAdvancesCalibration() {
        val detector = SquatStateMachine(config)
        repeat(20) { index -> detector.invalid(index * 100L) }

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertEquals(0, detector.repSequence)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        repeat(11) { index ->
            detector.valid(index * 100L, 170.0, 160.0, 0.25)
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
        detector.valid(start, 145.0, 140.0, 0.30),
        detector.valid(start + 100, 125.0, 130.0, 0.34),
        detector.valid(start + 200, 100.0, 110.0, 0.40),
        detector.valid(start + 300, 100.0, 110.0, 0.40),
    )

    private fun finishStanding(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 120.0, 125.0, 0.36),
        detector.valid(start + 200, 150.0, 145.0, 0.30),
        detector.valid(start + 400, 165.0, 155.0, 0.25),
        detector.valid(start + 650, 170.0, 160.0, 0.25),
    )

    private fun SquatStateMachine.valid(
        timestampMs: Long,
        knee: Double,
        hip: Double,
        hipY: Double,
    ) = process(
        PoseFeatureResult.Valid(
            PoseFeatureSample(
                timestampMs = timestampMs,
                kneeAngleDeg = knee,
                hipAngleDeg = hip,
                hipY = hipY,
                legLength = 0.50,
                confidence = 0.90,
                selectedSide = PoseSide.LEFT,
            ),
        ),
    )

    private fun SquatStateMachine.invalid(timestampMs: Long) =
        process(
            PoseFeatureResult.Invalid(
                timestampMs,
                PoseQualityWarning.SHOW_FULL_BODY,
            ),
        )
}
