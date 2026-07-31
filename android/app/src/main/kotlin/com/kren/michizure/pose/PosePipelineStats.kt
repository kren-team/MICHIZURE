package com.kren.michizure.pose

import java.util.ArrayDeque

class PosePipelineStats(
    private val maxSamples: Int = 180,
) {
    private val analyzerTimesNs = ArrayDeque<Long>()
    private val submitTimesNs = ArrayDeque<Long>()
    private val callbackTimesNs = ArrayDeque<Long>()
    private val validPoseTimesNs = ArrayDeque<Long>()
    private val preprocessingMs = ArrayDeque<Long>()
    private val inferenceMs = ArrayDeque<Long>()
    private val pipelineMs = ArrayDeque<Long>()
    private var analyzerFrames = 0L
    private var inferenceSubmitted = 0L
    private var resultCallbacks = 0L
    private var resultsWithPose = 0L
    private var resultsWithoutPose = 0L
    private var errorCallbacks = 0L
    private var firstSubmissionNs: Long? = null
    private var lastCallbackNs: Long? = null
    private var activeDelegate: PoseDelegate? = null
    private var activeDelegateSubmissions = 0L
    private var activeDelegateCallbacks = 0L
    private var lastError: String? = null
    private var droppedBeforePreprocessing = 0L
    private var rejectedAsBusy = 0L
    private var resultCount = 0L
    private var noPoseCount = 0L

    @Synchronized
    fun recordAnalyzerFrame(timestampNs: Long) {
        analyzerFrames += 1
        analyzerTimesNs.addLast(timestampNs)
        trim(analyzerTimesNs)
    }

    @Synchronized
    fun recordDroppedBeforePreprocessing() {
        droppedBeforePreprocessing += 1
    }

    @Synchronized
    fun recordRejectedAsBusy() {
        rejectedAsBusy += 1
    }

    @Synchronized
    fun recordSubmitted(
        timestampNs: Long,
        preprocessingDurationMs: Long,
        delegate: PoseDelegate,
    ) {
        inferenceSubmitted += 1
        activeDelegateSubmissions += 1
        if (firstSubmissionNs == null) firstSubmissionNs = timestampNs
        activeDelegate = delegate
        submitTimesNs.addLast(timestampNs)
        preprocessingMs.addLast(preprocessingDurationMs.coerceAtLeast(0))
        trim(submitTimesNs)
        trim(preprocessingMs)
    }

    @Synchronized
    fun recordResult(
        sample: PoseLatencySample,
        poseDetected: Boolean,
        validPose: Boolean,
    ) {
        resultCallbacks += 1
        activeDelegateCallbacks += 1
        lastCallbackNs = sample.inferenceCallbackNs
        callbackTimesNs.addLast(sample.inferenceCallbackNs)
        trim(callbackTimesNs)
        if (validPose) {
            validPoseTimesNs.addLast(sample.inferenceCallbackNs)
            trim(validPoseTimesNs)
        }
        resultCount += 1
        if (poseDetected) {
            resultsWithPose += 1
        } else {
            resultsWithoutPose += 1
            noPoseCount += 1
        }
        inferenceMs.addLast(sample.inferenceMs)
        pipelineMs.addLast(sample.nativePipelineMs)
        trim(inferenceMs)
        trim(pipelineMs)
    }

    @Synchronized
    fun recordError(
        timestampNs: Long,
        code: String,
    ) {
        errorCallbacks += 1
        lastCallbackNs = timestampNs
        lastError = code
    }

    @Synchronized
    fun recordRuntimeError(code: String) {
        lastError = code
    }

    @Synchronized
    fun setDelegate(delegate: PoseDelegate) {
        activeDelegate = delegate
        activeDelegateSubmissions = 0
        activeDelegateCallbacks = 0
        firstSubmissionNs = null
        lastCallbackNs = null
    }

    @Synchronized
    fun snapshot(nowNs: Long = System.nanoTime()): PosePipelineMetrics {
        val submittedFps = fps(submitTimesNs)
        return PosePipelineMetrics(
            sampleCount = inferenceMs.size,
            analyzerFrames = analyzerFrames,
            inferenceSubmitted = inferenceSubmitted,
            resultCallbacks = resultCallbacks,
            resultsWithPose = resultsWithPose,
            resultsWithoutPose = resultsWithoutPose,
            errorCallbacks = errorCallbacks,
            lastCallbackAgeMs = callbackAgeMs(nowNs),
            activeDelegate = activeDelegate,
            lastError = lastError,
            activeDelegateSubmissions = activeDelegateSubmissions,
            activeDelegateCallbacks = activeDelegateCallbacks,
            analyzerInputFps = fps(analyzerTimesNs),
            inferenceSubmittedFps = submittedFps,
            resultCallbackFps = fps(callbackTimesNs),
            validPoseFps = fps(validPoseTimesNs),
            actualAnalysisFps = submittedFps,
            droppedBeforePreprocessing = droppedBeforePreprocessing,
            rejectedAsBusy = rejectedAsBusy,
            resultCount = resultCount,
            noPoseCount = noPoseCount,
            preprocessingP50Ms = percentile(preprocessingMs, 0.50),
            preprocessingP95Ms = percentile(preprocessingMs, 0.95),
            inferenceP50Ms = percentile(inferenceMs, 0.50),
            inferenceP95Ms = percentile(inferenceMs, 0.95),
            nativePipelineP50Ms = percentile(pipelineMs, 0.50),
            nativePipelineP95Ms = percentile(pipelineMs, 0.95),
        )
    }

    @Synchronized
    fun reset() {
        analyzerTimesNs.clear()
        submitTimesNs.clear()
        callbackTimesNs.clear()
        validPoseTimesNs.clear()
        preprocessingMs.clear()
        inferenceMs.clear()
        pipelineMs.clear()
        analyzerFrames = 0
        inferenceSubmitted = 0
        resultCallbacks = 0
        resultsWithPose = 0
        resultsWithoutPose = 0
        errorCallbacks = 0
        firstSubmissionNs = null
        lastCallbackNs = null
        activeDelegate = null
        activeDelegateSubmissions = 0
        activeDelegateCallbacks = 0
        lastError = null
        droppedBeforePreprocessing = 0
        rejectedAsBusy = 0
        resultCount = 0
        noPoseCount = 0
    }

    private fun callbackAgeMs(nowNs: Long): Long? {
        val reference = lastCallbackNs ?: firstSubmissionNs ?: return null
        return ((nowNs - reference).coerceAtLeast(0) / NANOS_PER_MILLISECOND)
    }

    private fun <T> trim(values: ArrayDeque<T>) {
        while (values.size > maxSamples) values.removeFirst()
    }

    private fun fps(values: ArrayDeque<Long>): Double {
        if (values.size < 2) return 0.0
        val durationNs = values.last() - values.first()
        return if (durationNs <= 0) {
            0.0
        } else {
            (values.size - 1) * NANOS_PER_SECOND.toDouble() / durationNs
        }
    }

    private fun percentile(
        values: Collection<Long>,
        fraction: Double,
    ): Long? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val index = ((sorted.size - 1) * fraction).toInt()
        return sorted[index]
    }

    private companion object {
        const val NANOS_PER_MILLISECOND = 1_000_000L
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
