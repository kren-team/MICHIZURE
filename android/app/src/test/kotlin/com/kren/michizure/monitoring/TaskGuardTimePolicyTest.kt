package com.kren.michizure.monitoring

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TaskGuardTimePolicyTest {
    @Test
    fun normalWallAndElapsedProgressionIsContinuous() {
        assertFalse(
            TaskGuardTimePolicy.hasWallClockDiscontinuity(
                startedWallMs = 100_000,
                startedElapsedMs = 10_000,
                nowWallMs = 105_000,
                nowElapsedMs = 15_000,
            ),
        )
    }

    @Test
    fun wallRollbackAndLargeJumpAreDiscontinuities() {
        assertTrue(
            TaskGuardTimePolicy.hasWallClockDiscontinuity(
                startedWallMs = 100_000,
                startedElapsedMs = 10_000,
                nowWallMs = 20_000,
                nowElapsedMs = 15_000,
            ),
        )
        assertTrue(
            TaskGuardTimePolicy.hasWallClockDiscontinuity(
                startedWallMs = 100_000,
                startedElapsedMs = 10_000,
                nowWallMs = 200_001,
                nowElapsedMs = 15_000,
            ),
        )
    }
}
