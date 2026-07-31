package com.kren.michizure.pose

import org.junit.Assert.assertThrows
import org.junit.Test

class RgbaPlaneLayoutTest {
    @Test
    fun acceptsTightlyPackedRgbaPlane() {
        RgbaPlaneLayoutValidator.validate(
            RgbaPlaneLayout(
                width = 480,
                height = 640,
                rowStride = 480 * 4,
                pixelStride = 4,
                remainingBytes = 480 * 640 * 4,
            ),
        )
    }

    @Test
    fun acceptsRgbaPlaneWithRowPadding() {
        val rowStride = 2_048
        RgbaPlaneLayoutValidator.validate(
            RgbaPlaneLayout(
                width = 480,
                height = 640,
                rowStride = rowStride,
                pixelStride = 4,
                remainingBytes = rowStride * 640,
            ),
        )
    }

    @Test
    fun rejectsWrongPixelStrideAndTruncatedPlane() {
        assertThrows(IllegalArgumentException::class.java) {
            RgbaPlaneLayoutValidator.validate(
                RgbaPlaneLayout(
                    width = 480,
                    height = 640,
                    rowStride = 480 * 4,
                    pixelStride = 1,
                    remainingBytes = 480 * 640 * 4,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            RgbaPlaneLayoutValidator.validate(
                RgbaPlaneLayout(
                    width = 480,
                    height = 640,
                    rowStride = 2_048,
                    pixelStride = 4,
                    remainingBytes = 1_024,
                ),
            )
        }
    }
}
