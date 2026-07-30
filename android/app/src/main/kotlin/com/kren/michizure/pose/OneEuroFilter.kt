package com.kren.michizure.pose

import kotlin.math.PI
import kotlin.math.abs

/**
 * Timestamp-driven One-Euro filter.
 *
 * It never assumes a fixed camera FPS. Invalid samples are ignored, duplicate
 * timestamps keep the last output, and a long gap re-arms the filter without
 * interpolating across an unknown motion.
 */
class OneEuroFilter(
    private val minCutoff: Double,
    private val beta: Double,
    private val derivativeCutoff: Double,
    private val longGapMs: Long,
) {
    private var lastTimestampMs: Long? = null
    private var lastRaw: Double? = null
    private var filteredValue: Double? = null
    private var filteredDerivative: Double = 0.0

    init {
        require(minCutoff > 0 && minCutoff.isFinite())
        require(beta >= 0 && beta.isFinite())
        require(derivativeCutoff > 0 && derivativeCutoff.isFinite())
        require(longGapMs > 0)
    }

    fun filter(
        value: Double,
        timestampMs: Long,
    ): Double? {
        if (!value.isFinite()) return null
        val previousTimestamp = lastTimestampMs
        if (previousTimestamp == null ||
            timestampMs - previousTimestamp > longGapMs
        ) {
            resetTo(value, timestampMs)
            return value
        }
        if (timestampMs <= previousTimestamp) return filteredValue

        val dtSeconds = (timestampMs - previousTimestamp) / 1_000.0
        val previousRaw = requireNotNull(lastRaw)
        val derivative = (value - previousRaw) / dtSeconds
        val derivativeAlpha = smoothingAlpha(dtSeconds, derivativeCutoff)
        filteredDerivative =
            lowPass(
                current = derivative,
                previous = filteredDerivative,
                alpha = derivativeAlpha,
            )
        val cutoff = minCutoff + beta * abs(filteredDerivative)
        val valueAlpha = smoothingAlpha(dtSeconds, cutoff)
        val output =
            lowPass(
                current = value,
                previous = requireNotNull(filteredValue),
                alpha = valueAlpha,
            )
        lastTimestampMs = timestampMs
        lastRaw = value
        filteredValue = output
        return output
    }

    fun reset() {
        lastTimestampMs = null
        lastRaw = null
        filteredValue = null
        filteredDerivative = 0.0
    }

    private fun resetTo(
        value: Double,
        timestampMs: Long,
    ) {
        lastTimestampMs = timestampMs
        lastRaw = value
        filteredValue = value
        filteredDerivative = 0.0
    }

    private fun smoothingAlpha(
        dtSeconds: Double,
        cutoff: Double,
    ): Double {
        val tau = 1.0 / (2.0 * PI * cutoff)
        return 1.0 / (1.0 + tau / dtSeconds)
    }

    private fun lowPass(
        current: Double,
        previous: Double,
        alpha: Double,
    ): Double = alpha * current + (1.0 - alpha) * previous
}
