package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun calibrationUsesStableStandingSamples() {
        val detector = SquatStateMachine(config)
        repeat(10) { detector.valid(it * 100L, 170.0, 0.25) }
        assertEquals(SquatState.CALIBRATING, detector.state)

        detector.valid(1_000, 170.0, 0.25)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun normalSquatProducesExactlyOneRepAfterReturnToStanding() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, 1_100)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun tenNormalSquatsProduceExactlyTenRepsWithMonotonicSequence() {
        val detector = calibratedDetector()
        val sequences = mutableListOf<Int>()
        var start = 1_100L
        repeat(10) {
            sequences += normalRep(detector, start)
                .filter { update -> update.repCompleted }
                .map { update -> update.repSequence }
            detector.valid(start + 1_350, 170.0, 0.25)
            start += 1_600
        }

        assertEquals((1..10).toList(), sequences)
        assertEquals(10, detector.repSequence)
    }

    @Test
    fun tenShallowSquatsNeverCount() {
        val detector = calibratedDetector()
        var timestamp = 1_100L
        repeat(10) {
            listOf(
                detector.valid(timestamp, 148.0, 0.28),
                detector.valid(timestamp + 100, 142.0, 0.29),
                detector.valid(timestamp + 250, 130.0, 0.31),
                detector.valid(timestamp + 450, 160.0, 0.27),
                detector.valid(timestamp + 750, 170.0, 0.25),
            )
            timestamp += 1_000
        }
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun tooDeepMotionIsRejectedAndRequiresRecalibration() {
        val detector = calibratedDetector()
        detector.valid(1_100, 145.0, 0.29)
        detector.valid(1_200, 140.0, 0.30)
        val update = detector.valid(1_400, 50.0, 0.39)

        assertFalse(update.repCompleted)
        assertEquals(PoseQualityWarning.TOO_DEEP, update.qualityWarning)
        assertEquals(0, detector.repSequence)
        assertEquals(SquatState.CALIBRATING, detector.state)
    }

    @Test
    fun forwardBendHipDropWithoutKneeFlexionNeverCounts() {
        val detector = calibratedDetector()
        val updates =
            listOf(
                detector.valid(1_100, 168.0, 0.36),
                detector.valid(1_300, 166.0, 0.38),
                detector.valid(1_550, 170.0, 0.25),
            )

        assertFalse(updates.any { it.repCompleted })
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun bottomBounceAndIncompleteAscentDoNotDoubleCount() {
        val detector = calibratedDetector()
        val updates = normalDescent(detector, 1_100).toMutableList()
        updates += detector.valid(1_650, 125.0, 0.33)
        updates += detector.valid(1_750, 100.0, 0.36)
        updates += detector.valid(1_900, 125.0, 0.33)
        updates += detector.valid(2_000, 135.0, 0.32)
        updates += detector.valid(2_200, 160.0, 0.27)
        updates += detector.valid(2_450, 170.0, 0.25)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun duplicateAndOutOfOrderFramesCannotCreateAnotherRep() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, 1_100).toMutableList()
        updates += detector.valid(2_200, 90.0, 0.36)
        updates += detector.valid(2_100, 170.0, 0.25)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals("duplicateFrame", updates.last().diagnostics.latestRejectReason)
    }

    @Test
    fun shortPoseLossIsToleratedButLongPoseLossResets() {
        val short = calibratedDetector()
        val shortUpdates = normalDescent(short, 1_100).toMutableList()
        shortUpdates += short.invalid(1_600)
        shortUpdates += short.valid(1_700, 125.0, 0.33)
        shortUpdates += short.valid(1_800, 135.0, 0.32)
        shortUpdates += short.valid(2_000, 160.0, 0.27)
        shortUpdates += short.valid(2_250, 170.0, 0.25)
        assertEquals(1, shortUpdates.count { it.repCompleted })

        val long = calibratedDetector()
        normalDescent(long, 1_100)
        long.invalid(1_600)
        long.invalid(1_900)
        assertEquals(SquatState.CALIBRATING, long.state)
        assertEquals(0, long.repSequence)
    }

    @Test
    fun startAtBottomAndStandingJitterNeverCount() {
        val bottomStart = SquatStateMachine(config)
        repeat(15) { bottomStart.valid(it * 100L, 95.0, 0.36) }
        assertEquals(SquatState.CALIBRATING, bottomStart.state)

        val standing = calibratedDetector()
        repeat(20) {
            standing.valid(1_100 + it * 80L, 160.0 + (it % 3), 0.252)
        }
        assertEquals(0, standing.repSequence)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        repeat(11) { detector.valid(it * 100L, 170.0, 0.25) }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun normalRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = normalDescent(detector, start).toMutableList()
        updates += detector.valid(start + 550, 125.0, 0.33)
        updates += detector.valid(start + 650, 135.0, 0.32)
        updates += detector.valid(start + 850, 160.0, 0.27)
        updates += detector.valid(start + 1_100, 170.0, 0.25)
        return updates
    }

    private fun normalDescent(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 145.0, 0.29),
        detector.valid(start + 100, 140.0, 0.30),
        detector.valid(start + 200, 120.0, 0.32),
        detector.valid(start + 300, 100.0, 0.36),
        detector.valid(start + 450, 100.0, 0.36),
    )

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
                quality =
                    PoseQualityMetrics.EMPTY.copy(
                        trackingStatus = PoseTrackingStatus.NO_POSE,
                    ),
                rejectReason = "poseNotDetected",
            ),
        )
}
