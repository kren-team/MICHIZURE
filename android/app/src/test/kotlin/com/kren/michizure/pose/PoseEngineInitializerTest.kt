package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class PoseEngineInitializerTest {
    @Test
    fun gpuSuccessDoesNotCreateCpu() {
        val attempts = mutableListOf<PoseDelegate>()
        val initialized =
            PoseEngineInitializer { delegate ->
                attempts += delegate
                delegate.wireValue
            }.initialize(preferGpu = true)

        assertEquals(PoseDelegate.GPU, initialized.delegate)
        assertEquals(listOf(PoseDelegate.GPU), attempts)
    }

    @Test
    fun gpuFailureFallsBackOnceToCpu() {
        val attempts = mutableListOf<PoseDelegate>()
        val initialized =
            PoseEngineInitializer { delegate ->
                attempts += delegate
                if (delegate == PoseDelegate.GPU) error("gpu unavailable")
                "cpu-engine"
            }.initialize(preferGpu = true)

        assertEquals(PoseDelegate.CPU, initialized.delegate)
        assertEquals(listOf(PoseDelegate.GPU, PoseDelegate.CPU), attempts)
    }

    @Test
    fun cpuFailureIsTypedByCallerWithoutAnInitializationLoop() {
        val attempts = mutableListOf<PoseDelegate>()

        try {
            PoseEngineInitializer<String> { delegate ->
                attempts += delegate
                error("unavailable")
            }.initialize(preferGpu = true)
            fail("CPU initialization failure must propagate")
        } catch (_: IllegalStateException) {
            // expected
        }
        assertEquals(listOf(PoseDelegate.GPU, PoseDelegate.CPU), attempts)
    }
}
