package com.kren.michizure.pose

object PoseCoordinateNormalizer {
    fun outputSize(
        width: Int,
        height: Int,
        rotationDegrees: Int,
    ): Pair<Int, Int> =
        if (rotationDegrees == 90 || rotationDegrees == 270) {
            height to width
        } else {
            width to height
        }

    fun x(
        rawX: Double,
        imageWidth: Int,
        mirrorHorizontally: Boolean,
    ): Double = if (mirrorHorizontally) imageWidth - rawX else rawX
}
