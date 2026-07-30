package com.kren.michizure.pose

enum class PoseDelegate(val wireValue: String) {
    GPU("gpu"),
    CPU("cpu"),
}

data class PoseLatencySample(
    val analyzerReceivedNs: Long,
    val preprocessingStartedNs: Long,
    val inferenceSubmittedNs: Long,
    val inferenceCallbackNs: Long,
    val stateMachineCompletedNs: Long,
    val nativeEventDispatchedNs: Long?,
) {
    val preprocessingMs: Long
        get() = nanosToMillis(inferenceSubmittedNs - preprocessingStartedNs)
    val inferenceMs: Long
        get() = nanosToMillis(inferenceCallbackNs - inferenceSubmittedNs)
    val stateMachineMs: Long
        get() = nanosToMillis(stateMachineCompletedNs - inferenceCallbackNs)
    val nativePipelineMs: Long
        get() = nanosToMillis(stateMachineCompletedNs - analyzerReceivedNs)

    private fun nanosToMillis(value: Long): Long =
        (value.coerceAtLeast(0) / NANOS_PER_MILLISECOND)

    private companion object {
        const val NANOS_PER_MILLISECOND = 1_000_000L
    }
}

data class PosePipelineMetrics(
    val sampleCount: Int = 0,
    val actualAnalysisFps: Double = 0.0,
    val droppedBeforePreprocessing: Long = 0,
    val rejectedAsBusy: Long = 0,
    val resultCount: Long = 0,
    val noPoseCount: Long = 0,
    val inferenceP50Ms: Long? = null,
    val inferenceP95Ms: Long? = null,
    val nativePipelineP50Ms: Long? = null,
    val nativePipelineP95Ms: Long? = null,
)

data class PoseFrameDelivery(
    val feature: PoseFeatureResult,
    val latency: PoseLatencySample,
    val metrics: PosePipelineMetrics,
    val delegate: PoseDelegate,
)

data class PoseFrameCompletion(
    val stateMachineCompletedNs: Long,
    val nativeEventDispatchedNs: Long?,
)

data class InitializedPoseEngine<T>(
    val engine: T,
    val delegate: PoseDelegate,
)

/**
 * Small testable GPU-first / CPU-fallback policy. It never retries forever.
 */
class PoseEngineInitializer<T>(
    private val creator: (PoseDelegate) -> T,
) {
    fun initialize(preferGpu: Boolean): InitializedPoseEngine<T> {
        if (preferGpu) {
            runCatching { creator(PoseDelegate.GPU) }
                .getOrNull()
                ?.let { return InitializedPoseEngine(it, PoseDelegate.GPU) }
        }
        return InitializedPoseEngine(
            engine = creator(PoseDelegate.CPU),
            delegate = PoseDelegate.CPU,
        )
    }
}
