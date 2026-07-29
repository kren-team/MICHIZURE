package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Test

class PoseCoordinateNormalizerTest {
    @Test
    fun swapsDimensionsForQuarterTurns() {
        assertEquals(640 to 480, PoseCoordinateNormalizer.outputSize(480, 640, 90))
        assertEquals(640 to 480, PoseCoordinateNormalizer.outputSize(480, 640, 270))
        assertEquals(480 to 640, PoseCoordinateNormalizer.outputSize(480, 640, 0))
    }

    @Test
    fun mirrorsFrontCameraXWithoutChangingRearCamera() {
        assertEquals(80.0, PoseCoordinateNormalizer.x(20.0, 100, true), 0.001)
        assertEquals(20.0, PoseCoordinateNormalizer.x(20.0, 100, false), 0.001)
    }
}
