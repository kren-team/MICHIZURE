package com.kren.michizure.pose

import java.util.ArrayDeque

class PosePipelineStats(
    private val maxSamples: Int = 180,
) {
    private val submitTimesNs = ArrayDeque<Long>()
    private val inferenceMs = ArrayDeque<Long>()
    private val pipelineMs = ArrayDeque<Long>()
    private var droppedBeforePreprocessing = 0L
    private var rejectedAsBusy = 0L
    private var resultCount = 0L
    private var noPoseCount = 0L

    @Synchronized
    fun recordDroppedBeforePreprocessing() {
        droppedBeforePreprocessing += 1
    }

    @Synchronized
    fun recordRejectedAsBusy() {
        rejectedAsBusy += 1
    }

    @Synchronized
    fun recordSubmitted(timestampNs: Long) {
        submitTimesNs.addLast(timestampNs)
        trim(submitTimesNs)
    }

    @Synchronized
    fun recordResult(
        sample: PoseLatencySample,
        poseDetected: Boolean,
    ) {
        resultCount += 1
        if (!poseDetected) noPoseCount += 1
        inferenceMs.addLast(sample.inferenceMs)
        pipelineMs.addLast(sample.nativePipelineMs)
        trim(inferenceMs)
        trim(pipelineMs)
    }

    @Synchronized
    fun snapshot(): PosePipelineMetrics {
        val durationNs =
            if (submitTimesNs.size < 2) {
                0L
            } else {
                submitTimesNs.last() - submitTimesNs.first()
            }
        val fps =
            if (durationNs <= 0) {
                0.0
            } else {
                (submitTimesNs.size - 1) * NANOS_PER_SECOND.toDouble() / durationNs
            }
        return PosePipelineMetrics(
            sampleCount = inferenceMs.size,
            actualAnalysisFps = fps,
            droppedBeforePreprocessing = droppedBeforePreprocessing,
            rejectedAsBusy = rejectedAsBusy,
            resultCount = resultCount,
            noPoseCount = noPoseCount,
            inferenceP50Ms = percentile(inferenceMs, 0.50),
            inferenceP95Ms = percentile(inferenceMs, 0.95),
            nativePipelineP50Ms = percentile(pipelineMs, 0.50),
            nativePipelineP95Ms = percentile(pipelineMs, 0.95),
        )
    }

    @Synchronized
    fun reset() {
        submitTimesNs.clear()
        inferenceMs.clear()
        pipelineMs.clear()
        droppedBeforePreprocessing = 0
        rejectedAsBusy = 0
        resultCount = 0
        noPoseCount = 0
    }

    private fun <T> trim(values: ArrayDeque<T>) {
        while (values.size > maxSamples) values.removeFirst()
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
        const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
