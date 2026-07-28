package com.kren.michizure.monitoring

import kotlin.math.abs

object TaskGuardTimePolicy {
    const val WALL_CLOCK_TOLERANCE_MS = 60_000L

    fun hasWallClockDiscontinuity(
        startedWallMs: Long,
        startedElapsedMs: Long,
        nowWallMs: Long,
        nowElapsedMs: Long,
        toleranceMs: Long = WALL_CLOCK_TOLERANCE_MS,
    ): Boolean {
        require(toleranceMs >= 0)
        val expectedWallMs = startedWallMs + (nowElapsedMs - startedElapsedMs)
        return abs(nowWallMs - expectedWallMs) > toleranceMs
    }
}
