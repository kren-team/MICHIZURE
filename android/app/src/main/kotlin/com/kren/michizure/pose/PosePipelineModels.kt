package com.kren.michizure.pose

enum class PoseDelegate(val wireValue: String) {
    GPU("gpu"),
    CPU("cpu"),
}

enum class PosePipelineStatus(val wireValue: String) {
    INITIALIZING("initializing"),
    AWAITING_RESULT("awaitingResult"),
    NO_POSE("noPose"),
    HIP_UNAVAILABLE("hipUnavailable"),
    KNEE_UNAVAILABLE("kneeUnavailable"),
    ANKLE_UNAVAILABLE("ankleUnavailable"),
    CONFIDENCE_INSUFFICIENT("confidenceInsufficient"),
    VALID("valid"),
    FAILED("failed"),
    ;

    companion object {
        fun fromTracking(status: PoseTrackingStatus): PosePipelineStatus =
            when (status) {
                PoseTrackingStatus.NO_POSE -> NO_POSE
                PoseTrackingStatus.HIP_UNAVAILABLE -> HIP_UNAVAILABLE
                PoseTrackingStatus.KNEE_UNAVAILABLE -> KNEE_UNAVAILABLE
                PoseTrackingStatus.ANKLE_UNAVAILABLE -> ANKLE_UNAVAILABLE
                PoseTrackingStatus.CONFIDENCE_INSUFFICIENT -> CONFIDENCE_INSUFFICIENT
                PoseTrackingStatus.VALID -> VALID
            }
    }
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
    val analyzerFrames: Long = 0,
    val inferenceSubmitted: Long = 0,
    val resultCallbacks: Long = 0,
    val resultsWithPose: Long = 0,
    val resultsWithoutPose: Long = 0,
    val errorCallbacks: Long = 0,
    val lastCallbackAgeMs: Long? = null,
    val activeDelegate: PoseDelegate? = null,
    val lastError: String? = null,
    val activeDelegateSubmissions: Long = 0,
    val activeDelegateCallbacks: Long = 0,
    val actualAnalysisFps: Double = 0.0,
    val droppedBeforePreprocessing: Long = 0,
    val rejectedAsBusy: Long = 0,
    val resultCount: Long = 0,
    val noPoseCount: Long = 0,
    val preprocessingP50Ms: Long? = null,
    val preprocessingP95Ms: Long? = null,
    val inferenceP50Ms: Long? = null,
    val inferenceP95Ms: Long? = null,
    val nativePipelineP50Ms: Long? = null,
    val nativePipelineP95Ms: Long? = null,
)

data class PosePipelineStatusSnapshot(
    val status: PosePipelineStatus,
    val metrics: PosePipelineMetrics,
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
    val state: SquatState = SquatState.CALIBRATING,
    val trackingStatus: PoseTrackingStatus = PoseTrackingStatus.NO_POSE,
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

enum class PoseRuntimeRecoveryAction {
    NONE,
    FALLBACK_TO_CPU,
    FAIL_CPU,
}

/**
 * Detects a live-stream engine that accepted frames but never produced a callback.
 *
 * The action is emitted at most once. GPU can fall back to CPU once; a CPU timeout
 * is surfaced as a typed failure rather than entering a restart loop.
 */
class PoseCallbackWatchdog(
    private val minimumSubmissions: Long = 5,
    private val callbackTimeoutMs: Long = 2_000,
) {
    private var terminalActionEmitted = false

    fun evaluate(metrics: PosePipelineMetrics): PoseRuntimeRecoveryAction {
        if (terminalActionEmitted ||
            metrics.activeDelegateSubmissions < minimumSubmissions ||
            metrics.activeDelegateCallbacks > 0 ||
            (metrics.lastCallbackAgeMs ?: 0) < callbackTimeoutMs
        ) {
            return PoseRuntimeRecoveryAction.NONE
        }
        terminalActionEmitted = true
        return if (metrics.activeDelegate == PoseDelegate.GPU) {
            PoseRuntimeRecoveryAction.FALLBACK_TO_CPU
        } else {
            PoseRuntimeRecoveryAction.FAIL_CPU
        }
    }

    fun reset() {
        terminalActionEmitted = false
    }
}
