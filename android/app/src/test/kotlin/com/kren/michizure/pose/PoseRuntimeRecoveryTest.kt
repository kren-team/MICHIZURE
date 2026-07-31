package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PoseRuntimeRecoveryTest {
    @Test
    fun emulatorRuntimeIsDetectedFromRanchuHardware() {
        val environment =
            AndroidRuntimeEnvironment(
                fingerprint = "google/sdk_gphone64_arm64/emu64a:36/test",
                model = "sdk_gphone64_arm64",
                manufacturer = "Google",
                brand = "google",
                device = "emu64a",
                product = "sdk_gphone64_arm64",
                hardware = "ranchu",
        )

        assertTrue(environment.isEmulator)
        assertFalse(environment.shouldPreferGpu(configPreference = true))
    }

    @Test
    fun physicalRuntimeDoesNotMatchEmulatorMarkers() {
        val environment =
            AndroidRuntimeEnvironment(
                fingerprint = "google/panther/panther:16/release",
                model = "Pixel 7",
                manufacturer = "Google",
                brand = "google",
                device = "panther",
                product = "panther",
                hardware = "gs201",
            )

        assertFalse(environment.isEmulator)
        assertTrue(environment.shouldPreferGpu(configPreference = true))
        assertFalse(environment.shouldPreferGpu(configPreference = false))
    }

    @Test
    fun gpuWithFiveSubmissionsAndNoCallbackFallsBackExactlyOnce() {
        val watchdog = PoseCallbackWatchdog()
        val timedOut =
            PosePipelineMetrics(
                activeDelegate = PoseDelegate.GPU,
                activeDelegateSubmissions = 5,
                activeDelegateCallbacks = 0,
                lastCallbackAgeMs = 2_000,
            )

        assertEquals(
            PoseRuntimeRecoveryAction.FALLBACK_TO_CPU,
            watchdog.evaluate(timedOut),
        )
        assertEquals(PoseRuntimeRecoveryAction.NONE, watchdog.evaluate(timedOut))
    }

    @Test
    fun anyGpuCallbackPreventsNoCallbackFallback() {
        val watchdog = PoseCallbackWatchdog()

        assertEquals(
            PoseRuntimeRecoveryAction.NONE,
            watchdog.evaluate(
                PosePipelineMetrics(
                    activeDelegate = PoseDelegate.GPU,
                    activeDelegateSubmissions = 10,
                    activeDelegateCallbacks = 1,
                    lastCallbackAgeMs = 5_000,
                ),
            ),
        )
    }

    @Test
    fun cpuTimeoutFailsWithoutStartingFallbackLoop() {
        val watchdog = PoseCallbackWatchdog()
        val timedOut =
            PosePipelineMetrics(
                activeDelegate = PoseDelegate.CPU,
                activeDelegateSubmissions = 5,
                activeDelegateCallbacks = 0,
                lastCallbackAgeMs = 2_001,
            )

        assertEquals(PoseRuntimeRecoveryAction.FAIL_CPU, watchdog.evaluate(timedOut))
        assertEquals(PoseRuntimeRecoveryAction.NONE, watchdog.evaluate(timedOut))
    }
}
