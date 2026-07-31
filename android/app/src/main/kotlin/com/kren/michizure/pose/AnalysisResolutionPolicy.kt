package com.kren.michizure.pose

import kotlin.math.abs

data class ImageDimensions(
    val width: Int,
    val height: Int,
) {
    val longEdge: Int = maxOf(width, height)
    val shortEdge: Int = minOf(width, height)
    val pixels: Int = width * height

    fun sameOrientationIndependentSize(other: ImageDimensions): Boolean =
        longEdge == other.longEdge && shortEdge == other.shortEdge
}

/** Orders CameraX-supported analysis sizes without changing Preview. */
object AnalysisResolutionPolicy {
    val requested = ImageDimensions(320, 240)

    private val explicitPriorities =
        listOf(
            requested,
            ImageDimensions(256, 192),
            ImageDimensions(320, 180),
        )
    private val finalFallback = ImageDimensions(640, 480)

    fun order(supported: List<ImageDimensions>): List<ImageDimensions> =
        supported.withIndex()
            .sortedWith(
                compareBy<IndexedValue<ImageDimensions>>(
                    { priorityBucket(it.value) },
                    { priorityDistance(it.value) },
                    { it.index },
                ),
            ).map { it.value }

    private fun priorityBucket(size: ImageDimensions): Int {
        explicitPriorities.indexOfFirst(size::sameOrientationIndependentSize)
            .takeIf { it >= 0 }
            ?.let { return it }
        if (isLowResolutionFourByThree(size)) return 3
        if (size.sameOrientationIndependentSize(finalFallback)) return 4
        return 5
    }

    private fun priorityDistance(size: ImageDimensions): Int =
        when (priorityBucket(size)) {
            3 -> abs(size.pixels - requested.pixels)
            5 ->
                aspectRatioDistance(size) * 1_000_000 +
                    abs(size.pixels - finalFallback.pixels)
            else -> 0
        }

    private fun isLowResolutionFourByThree(size: ImageDimensions): Boolean =
        size.longEdge * 3 == size.shortEdge * 4 &&
            size.pixels < finalFallback.pixels

    private fun aspectRatioDistance(size: ImageDimensions): Int =
        abs(size.longEdge * 3 - size.shortEdge * 4)
}
