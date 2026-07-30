package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun calibrationEstablishesStandingHipKneeGap() {
        val detector = SquatStateMachine(config)
        val updates =
            (0..10).map { index ->
                detector.valid(index * 100L, hipY = 0.25, kneeY = 0.50)
            }

        assertEquals(SquatState.STANDING, detector.state)
        assertEquals(SquatState.CALIBRATING, updates.first().state)
        assertEquals(SquatState.STANDING, updates.last().state)
    }

    @Test
    fun standingDescendingBandOverlapBottomAndAscentAreDistinct() {
        val detector = calibratedDetector()

        assertEquals(SquatState.STANDING, detector.valid(1_100, 0.25, 0.50).state)
        assertEquals(SquatState.STANDING, detector.valid(1_200, 0.29, 0.45).state)
        assertEquals(SquatState.DESCENDING, detector.valid(1_300, 0.30, 0.46).state)
        detector.valid(1_500, 0.35, 0.42)
        val bottom = detector.valid(1_600, 0.35, 0.42)
        assertEquals(SquatState.BOTTOM, bottom.state)
        assertTrue(requireNotNull(bottom.diagnostics.normalizedVerticalGap) <= 0.30)
        detector.valid(1_800, 0.31, 0.44)
        assertEquals(SquatState.ASCENDING, detector.valid(1_900, 0.31, 0.44).state)
    }

    @Test
    fun normalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()

        val updates = normalRep(detector, 1_100)

        assertEquals(
            updates.joinToString { "${it.state}:${it.diagnostics.latestRejectReason}" },
            1,
            updates.count { it.repCompleted },
        )
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun tenNormalSquatsProduceExactlyTenMonotonicEvents() {
        val detector = calibratedDetector()
        val completed = mutableListOf<Int>()
        var start = 1_100L
        repeat(10) {
            completed +=
                normalRep(detector, start)
                    .filter { update -> update.repCompleted }
                    .map { update -> update.repSequence }
            start += 1_600
        }

        assertEquals((1..10).toList(), completed)
        assertEquals(10, detector.repSequence)
    }

    @Test
    fun gapCompressionWithoutHipDropDoesNotReachBottom() {
        val detector = calibratedDetector()
        val updates = listOf(
            detector.valid(1_100, 0.26, 0.33),
            detector.valid(1_200, 0.26, 0.33),
            detector.valid(1_400, 0.25, 0.50),
        )

        assertFalse(updates.any { it.repCompleted })
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun hipDropWithoutGapCompressionModelsForwardBendAndDoesNotCount() {
        val detector = calibratedDetector()
        val updates = listOf(
            detector.valid(1_100, 0.35, 0.60),
            detector.valid(1_200, 0.36, 0.61),
            detector.valid(1_400, 0.25, 0.50),
        )

        assertFalse(updates.any { it.repCompleted })
        assertEquals(SquatState.STANDING, detector.state)
    }

    @Test
    fun shallowSquatIncompleteDescentAndIncompleteAscentDoNotCount() {
        val shallow = calibratedDetector()
        val shallowUpdates = listOf(
            shallow.valid(1_100, 0.29, 0.45),
            shallow.valid(1_200, 0.30, 0.46),
            shallow.valid(1_400, 0.29, 0.46),
            shallow.valid(1_600, 0.25, 0.50),
        )
        assertFalse(shallowUpdates.any { it.repCompleted })

        val incompleteAscent = calibratedDetector()
        val updates = descendToBottom(incompleteAscent, 1_100).toMutableList()
        updates += incompleteAscent.valid(1_800, 0.31, 0.44)
        updates += incompleteAscent.valid(1_900, 0.31, 0.44)
        updates += incompleteAscent.valid(2_100, 0.29, 0.45)
        assertFalse(updates.any { it.repCompleted })
    }

    @Test
    fun duplicateFramesPoseLossAndJitterCannotCreateExtraRep() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, 1_100).toMutableList()
        updates += detector.valid(2_400, 0.25, 0.50)
        updates += detector.valid(2_400, 0.35, 0.42)
        updates += detector.valid(2_300, 0.35, 0.42)
        assertEquals(1, updates.count { it.repCompleted })
        assertEquals("duplicateFrame", updates.last().diagnostics.latestRejectReason)

        val lost = calibratedDetector()
        lost.valid(1_100, 0.29, 0.45)
        lost.valid(1_200, 0.30, 0.46)
        lost.invalid(1_300)
        lost.invalid(1_600)
        assertEquals(SquatState.CALIBRATING, lost.state)
        assertEquals(0, lost.repSequence)
    }

    private fun calibratedDetector(): SquatStateMachine {
        val detector = SquatStateMachine(config)
        repeat(11) { index ->
            detector.valid(index * 100L, hipY = 0.25, kneeY = 0.50)
        }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun normalRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = descendToBottom(detector, start).toMutableList()
        updates += detector.valid(start + 500, 0.31, 0.44)
        updates += detector.valid(start + 600, 0.31, 0.44)
        updates += detector.valid(start + 700, 0.25, 0.50)
        updates += detector.valid(start + 900, 0.25, 0.50)
        updates += detector.valid(start + 1_000, 0.25, 0.50)
        updates += detector.valid(start + 1_200, 0.25, 0.50)
        updates += detector.valid(start + 1_400, 0.25, 0.50)
        return updates
    }

    private fun descendToBottom(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 0.29, 0.45),
        detector.valid(start + 100, 0.30, 0.46),
        detector.valid(start + 200, 0.35, 0.42),
        detector.valid(start + 300, 0.35, 0.42),
        detector.valid(start + 400, 0.35, 0.42),
    )

    private fun SquatStateMachine.valid(
        timestampMs: Long,
        hipY: Double,
        kneeY: Double,
    ) = process(
        PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = timestampMs,
                    hipY = hipY,
                    kneeY = kneeY,
                    confidence = 0.90,
                    selectedSide = PoseSide.LEFT,
                ),
            quality =
                PoseQualityMetrics.EMPTY.copy(
                    poseDetected = true,
                    trackingStatus = PoseTrackingStatus.VALID,
                    selectedSide = PoseSide.LEFT,
                ),
        ),
    )

    private fun SquatStateMachine.invalid(timestampMs: Long) =
        process(
            PoseFeatureResult.Invalid(
                timestampMs,
                PoseQualityWarning.NO_POSE_DETECTED,
                rejectReason = "poseNotDetected",
            ),
        )
}
