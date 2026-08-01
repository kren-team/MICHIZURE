package com.kren.michizure.pose

import java.util.Locale

object SquatDebugTraceFormatter {
    fun trace(update: SquatDetectorUpdate, metrics: PosePipelineMetrics): String {
        val diagnostics = update.diagnostics
        return listOf(
            "phase=${update.state.name}",
            "prev=${diagnostics.previousState?.name ?: "-"}",
            "knee=${metric(diagnostics.kneeAngleDeg)}",
            "standing=${metric(diagnostics.calibratedStandingKneeAngleDeg)}",
            "bend=${metric(diagnostics.kneeBendDeltaDeg)}",
            "minKnee=${metric(diagnostics.minimumAttemptKneeAngleDeg)}",
            "hipDrop=${metric(diagnostics.normalizedHipDrop, 3)}",
            "maxHipDrop=${metric(diagnostics.maximumAttemptHipDropRatio, 3)}",
            "score=${diagnostics.bottomEvidenceScore}",
            "evidence=${diagnostics.bottomEvidencePath?.wireValue ?: "NONE"}",
            "bottom=${diagnostics.bottomReached}",
            "candidateCount=${diagnostics.calibrationSampleCount}",
            "strongCandidates=${diagnostics.strongStandingCandidateCount}",
            "provisional=${metric(diagnostics.provisionalStandingAngleDeg)}",
            "calMedian=${metric(diagnostics.calibrationMedianAngleDeg)}",
            "calRange=${metric(diagnostics.calibrationAngleRangeDeg)}",
            "calWindowMs=${diagnostics.calibrationWindowAgeMs ?: -1}",
            "calTimeoutMs=${diagnostics.calibrationTimeoutMs}",
            "calQuality=${diagnostics.calibrationQualityPath?.wireValue ?: "-"}",
            "calReject=${diagnostics.lastCalibrationRejectReason ?: "-"}",
            "bufferPreserved=${diagnostics.candidateBufferPreserved}",
            "autoCalibrated=${diagnostics.autoCalibratedOnDescent}",
            "baselineSource=${diagnostics.standingBaselineSource ?: "-"}",
            "dtMs=${diagnostics.frameDtMs ?: -1}",
            "poseAgeMs=${diagnostics.validPoseAgeMs ?: -1}",
            "fps=${metric(metrics.validPoseFps, 1)}",
            "reason=${diagnostics.lastTransitionReason ?: diagnostics.latestRejectReason ?: "-"}",
        ).joinToString(" ")
    }

    fun performance(metrics: PosePipelineMetrics): String =
        listOf(
            "inputFps=${metric(metrics.analyzerInputFps, 1)}",
            "submitFps=${metric(metrics.inferenceSubmittedFps, 1)}",
            "callbackFps=${metric(metrics.resultCallbackFps, 1)}",
            "validFps=${metric(metrics.validPoseFps, 1)}",
            "throttleDrop=${metrics.droppedBeforePreprocessing}",
            "busyDrop=${metrics.rejectedAsBusy}",
            "converted=${metrics.convertedBitmapCount}",
            "rotated=${metrics.rotationBitmapCount}",
            "preP95Ms=${metrics.preprocessingP95Ms ?: -1}",
            "inferenceP95Ms=${metrics.inferenceP95Ms ?: -1}",
            "pipelineP95Ms=${metrics.nativePipelineP95Ms ?: -1}",
        ).joinToString(" ")

    private fun metric(value: Double?, digits: Int = 1): String =
        value?.let { String.format(Locale.US, "%.${digits}f", it) } ?: "-"
}
