package com.kren.michizure.pose

data class RgbaPlaneLayout(
    val width: Int,
    val height: Int,
    val rowStride: Int,
    val pixelStride: Int,
    val remainingBytes: Int,
)

/**
 * Audits CameraX RGBA metadata before delegating stride-aware conversion to
 * ImageProxy.toBitmap(). A tightly packed width*height*4 buffer is never assumed.
 */
object RgbaPlaneLayoutValidator {
    fun validate(layout: RgbaPlaneLayout) {
        require(layout.width > 0 && layout.height > 0)
        require(layout.pixelStride == RGBA_BYTES_PER_PIXEL)
        val minimumRowBytes =
            (layout.width - 1).toLong() * layout.pixelStride + RGBA_BYTES_PER_PIXEL
        require(layout.rowStride.toLong() >= minimumRowBytes)
        val minimumBufferBytes =
            (layout.height - 1).toLong() * layout.rowStride + minimumRowBytes
        require(layout.remainingBytes.toLong() >= minimumBufferBytes)
    }

    private const val RGBA_BYTES_PER_PIXEL = 4
}
