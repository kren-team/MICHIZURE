package com.kren.michizure.pose

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OneEuroFilterTest {
    @Test
    fun constantInputConvergesAndReducesJitter() {
        val filter = filter()
        val raw = listOf(10.0, 10.3, 9.7, 10.2, 9.8, 10.0)
        val output = raw.mapIndexed { index, value -> filter.filter(value, index * 67L)!! }

        assertTrue(range(output.drop(1)) < range(raw))
        assertTrue(abs(output.last() - 10.0) < 0.2)
    }

    @Test
    fun fastMotionRespondsMoreThanSlowCutoffOnlyFilter() {
        val adaptive = filter(beta = 0.20)
        val static = filter(beta = 0.0)
        adaptive.filter(0.0, 0)
        static.filter(0.0, 0)

        val adaptiveStep = adaptive.filter(10.0, 67)!!
        val staticStep = static.filter(10.0, 67)!!

        assertTrue(adaptiveStep > staticStep)
        assertTrue(adaptiveStep > 0)
        assertTrue(adaptiveStep < 10)
    }

    @Test
    fun variableIntervalsDuplicateReverseAndLongGapAreSafe() {
        val filter = filter()
        assertEquals(1.0, filter.filter(1.0, 100)!!, 0.0001)
        val variable = filter.filter(2.0, 180)!!
        assertEquals(variable, filter.filter(3.0, 180)!!, 0.0001)
        assertEquals(variable, filter.filter(4.0, 170)!!, 0.0001)
        assertEquals(8.0, filter.filter(8.0, 1_000)!!, 0.0001)
    }

    @Test
    fun nanIsRejectedAndResetRearmsImmediately() {
        val filter = filter()
        filter.filter(1.0, 0)
        assertNull(filter.filter(Double.NaN, 67))
        filter.reset()
        assertEquals(9.0, filter.filter(9.0, 100)!!, 0.0001)
    }

    @Test
    fun leftAndRightCoordinatesKeepIndependentFilterHistory() {
        val filter = LowerBodyPoseFilter()
        val leftFirst = filter.filter(pose(0, leftX = 10.0, rightX = 90.0))
        val switched = filter.filter(pose(67, leftX = 11.0, rightX = 89.0))

        assertTrue(requireNotNull(leftFirst.left?.hip).x < 20)
        assertTrue(requireNotNull(switched.right?.hip).x > 80)
    }

    private fun filter(beta: Double = 0.02) =
        OneEuroFilter(
            minCutoff = 1.0,
            beta = beta,
            derivativeCutoff = 1.0,
            longGapMs = 500,
        )

    private fun range(values: List<Double>): Double =
        requireNotNull(values.maxOrNull()) - requireNotNull(values.minOrNull())

    private fun pose(
        timestampMs: Long,
        leftX: Double,
        rightX: Double,
    ) = LowerBodyPose(
        timestampMs = timestampMs,
        imageWidth = 100,
        imageHeight = 100,
        poseDetected = true,
        left = side(leftX),
        right = side(rightX),
    )

    private fun side(x: Double) =
        LowerBodySide(
            hip = PosePoint(x, 20.0, 0.9),
            knee = PosePoint(x, 50.0, 0.9),
            ankle = PosePoint(x, 80.0, 0.9),
        )
}
