package com.kren.michizure.pose

data class SupportedFrameRateRange(
    val lower: Int,
    val upper: Int,
)

/** Selects only a range reported by the active camera. */
object CameraFrameRatePolicy {
    fun select(available: Collection<SupportedFrameRateRange>): SupportedFrameRateRange? {
        val valid = available.filter { it.lower > 0 && it.upper >= it.lower }
        valid.firstOrNull { it.lower == 30 && it.upper == 30 }?.let { return it }
        valid.filter { it.lower >= 15 }
            .minWithOrNull(
                compareBy<SupportedFrameRateRange> { kotlin.math.abs(it.upper - 30) }
                    .thenBy { kotlin.math.abs(it.lower - 30) },
            )
            ?.let { return it }
        return valid.filter { it.lower <= 15 && it.upper >= 30 }
            .maxByOrNull { it.lower }
    }
}
