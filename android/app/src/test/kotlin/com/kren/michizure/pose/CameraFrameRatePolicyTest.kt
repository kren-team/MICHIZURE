package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CameraFrameRatePolicyTest {
    @Test
    fun exactThirtyFpsWins() {
        assertEquals(
            SupportedFrameRateRange(30, 30),
            CameraFrameRatePolicy.select(
                listOf(
                    SupportedFrameRateRange(15, 30),
                    SupportedFrameRateRange(24, 30),
                    SupportedFrameRateRange(30, 30),
                ),
            ),
        )
    }

    @Test
    fun supportedRangeWithLowerBoundAtLeastFifteenWinsNext() {
        assertEquals(
            SupportedFrameRateRange(24, 30),
            CameraFrameRatePolicy.select(
                listOf(
                    SupportedFrameRateRange(2, 30),
                    SupportedFrameRateRange(15, 24),
                    SupportedFrameRateRange(24, 30),
                ),
            ),
        )
    }

    @Test
    fun broadFifteenToThirtyEquivalentIsFallback() {
        assertEquals(
            SupportedFrameRateRange(10, 30),
            CameraFrameRatePolicy.select(
                listOf(
                    SupportedFrameRateRange(2, 30),
                    SupportedFrameRateRange(10, 30),
                ),
            ),
        )
    }

    @Test
    fun unsupportedRangesLeaveCameraXDefaultUntouched() {
        assertNull(
            CameraFrameRatePolicy.select(
                listOf(SupportedFrameRateRange(2, 12)),
            ),
        )
    }
}
