package com.kren.michizure.pose

import android.content.pm.ApplicationInfo
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import java.util.ArrayDeque
import java.util.Locale

data class NativeSquatSession(
    val squatSessionId: String,
    val debtId: String,
)

class SquatSessionManager(
    private val lifecycleOwner: LifecycleOwner,
    private val runtimeEnvironment: AndroidRuntimeEnvironment =
        AndroidRuntimeEnvironment.current(),
    private val sourceFactory: (
        SquatCameraContainer,
        LifecycleOwner,
        (PoseDelegate) -> Unit,
        (PosePipelineStatusSnapshot) -> Unit,
        (PoseFrameDelivery) -> PoseFrameCompletion,
        (String) -> Unit,
    ) -> PoseSource = { view, owner, onReady, onStatus, onFrame, onFailure ->
        CameraMediaPipePoseSource(
            context = view.context.applicationContext,
            lifecycleOwner = owner,
            cameraContainer = view,
            onReady = onReady,
            onStatus = onStatus,
            onFrame = onFrame,
            onFailure = onFailure,
        )
    },
) : AutoCloseable {
    private val detectorConfig = SquatDetectorConfig()
    private var session: NativeSquatSession? = null
    private var previewView: SquatCameraContainer? = null
    private var source: PoseSource? = null
    private var machine = SquatStateMachine(detectorConfig, runtimeEnvironment.isEmulator)
    private var lastState: SquatState? = null
    private var lastWarning: PoseQualityWarning? = null
    private var lastPipelineStatus: PosePipelineStatus? = null
    private var pipelineStatus = PosePipelineStatus.INITIALIZING
    private var lastUpdate: SquatDetectorUpdate? = null
    private var lastDiagnosticsEmitMs = Long.MIN_VALUE
    private var lastDiagnosticsPayload: Map<String, Any?>? = null
    private val diagnosticEmitTimesMs = ArrayDeque<Long>()
    private val latenciesMs = ArrayDeque<Long>()
    private var delegate: PoseDelegate? = null
    private var debugThumbnailEnabled = false
    private var lastPerfLogMs = Long.MIN_VALUE
    private var lastLoggedTransitionKey: String? = null
    private var lastLoggedRepSequence = 0
    private var lastLoggedRejectKey: String? = null
    private var lastLoggedResetKey: String? = null

    @Synchronized
    fun attachPreview(view: SquatCameraContainer) {
        previewView = view
        view.setDebugThumbnailEnabled(debugThumbnailEnabled)
        startSourceIfReady()
    }

    @Synchronized
    fun setDebugThumbnailEnabled(enabled: Boolean) {
        debugThumbnailEnabled = enabled
        previewView?.setDebugThumbnailEnabled(enabled)
    }

    @Synchronized
    fun detachPreview(view: SquatCameraContainer) {
        if (previewView !== view) return
        previewView = null
        source?.close()
        source = null
    }

    @Synchronized
    fun start(newSession: NativeSquatSession): Boolean {
        val current = session
        if (current == newSession) {
            startSourceIfReady()
            return false
        }
        check(current == null) { "A different squat session is already active" }
        session = newSession
        machine = SquatStateMachine(detectorConfig, runtimeEnvironment.isEmulator)
        lastState = null
        lastWarning = null
        lastPipelineStatus = null
        pipelineStatus = PosePipelineStatus.INITIALIZING
        lastUpdate = null
        latenciesMs.clear()
        diagnosticEmitTimesMs.clear()
        lastDiagnosticsEmitMs = Long.MIN_VALUE
        lastDiagnosticsPayload = null
        delegate = null
        resetDebugLogState()
        emit(
            type = "calibrating",
            values =
                mapOf(
                    "state" to SquatState.CALIBRATING.wireValue,
                    "quality" to PoseQualityWarning.HOLD_STILL_TO_CALIBRATE.wireValue,
                    "squatSessionId" to newSession.squatSessionId,
                ),
        )
        startSourceIfReady()
        return true
    }

    @Synchronized
    fun stop(squatSessionId: String?): Boolean {
        val current = session ?: return false
        if (squatSessionId != null && current.squatSessionId != squatSessionId) {
            return false
        }
        source?.close()
        source = null
        session = null
        machine.reset()
        lastState = null
        lastWarning = null
        lastPipelineStatus = null
        pipelineStatus = PosePipelineStatus.INITIALIZING
        lastUpdate = null
        latenciesMs.clear()
        diagnosticEmitTimesMs.clear()
        lastDiagnosticsEmitMs = Long.MIN_VALUE
        lastDiagnosticsPayload = null
        delegate = null
        resetDebugLogState()
        return true
    }

    @Synchronized
    fun statePayload(): Map<String, Any?> {
        val current = session
        return SquatContract.versioned(
            mapOf(
                "isRunning" to (current != null),
                "squatSessionId" to current?.squatSessionId,
                "debtId" to current?.debtId,
                "detectorState" to machine.state.wireValue,
                "pipelineStatus" to pipelineStatus.wireValue,
                "repSequence" to machine.repSequence,
                "latencyP95Ms" to latencyP95(),
            ),
        )
    }

    @Synchronized
    private fun startSourceIfReady() {
        session ?: return
        val view = previewView ?: return
        if (source != null) return
        source =
            sourceFactory(
                view,
                lifecycleOwner,
                ::onDetectorReady,
                ::onPipelineStatus,
                ::onFrame,
                ::onDetectorFailure,
            ).also { it.start() }
    }

    @Synchronized
    private fun onDetectorReady(selectedDelegate: PoseDelegate) {
        val currentSession = session ?: return
        delegate = selectedDelegate
        emit(
            type = "detectorReady",
            values =
                mapOf(
                    "detectorType" to "mediapipe",
                    "detectorVersion" to SquatDetectorConfig.VERSION,
                    "delegate" to selectedDelegate.wireValue,
                    "squatSessionId" to currentSession.squatSessionId,
                ),
        )
    }

    @Synchronized
    private fun onPipelineStatus(snapshot: PosePipelineStatusSnapshot) {
        val current = session ?: return
        pipelineStatus = snapshot.status
        logPosePerformance(snapshot.metrics)
        if (snapshot.status != lastPipelineStatus) {
            lastPipelineStatus = snapshot.status
            emit(
                type = "pipelineStatusChanged",
                values =
                    mapOf(
                        "squatSessionId" to current.squatSessionId,
                        "status" to snapshot.status.wireValue,
                    ),
            )
        }
        emitDiagnosticsIfDue(
            current = current,
            update = lastUpdate,
            latencyMs = null,
            metrics = snapshot.metrics,
        )
    }

    @Synchronized
    private fun onFrame(delivery: PoseFrameDelivery): PoseFrameCompletion {
        val current =
            session
                ?: return PoseFrameCompletion(
                    stateMachineCompletedNs = elapsedNs(),
                    nativeEventDispatchedNs = null,
                    state = machine.state,
                    trackingStatus = PoseTrackingStatus.NO_POSE,
                )
        val feature = delivery.feature
        val update = machine.process(feature)
        lastUpdate = update
        logSquatFrame(update, delivery.metrics)
        val stateMachineCompletedNs = elapsedNs()
        val latency =
            delivery.latency.copy(
                stateMachineCompletedNs = stateMachineCompletedNs,
            )
        val latencyMs = latency.nativePipelineMs
        latenciesMs.addLast(latencyMs)
        while (latenciesMs.size > MAX_LATENCY_SAMPLES) latenciesMs.removeFirst()
        emitDiagnosticsIfDue(current, update, latencyMs, delivery.metrics)
        var lastDispatchNs: Long? = null
        if (update.state != lastState) {
            lastState = update.state
            lastDispatchNs =
                emit(
                type = "stateChanged",
                values =
                    mapOf(
                        "state" to update.state.wireValue,
                        "squatSessionId" to current.squatSessionId,
                        "analysisLatencyMs" to latencyMs,
                    ),
                )
        }
        if (update.qualityWarning != lastWarning) {
            lastWarning = update.qualityWarning
            lastDispatchNs =
                emit(
                type = "qualityWarning",
                values =
                    mapOf(
                        "quality" to update.qualityWarning?.wireValue,
                        "squatSessionId" to current.squatSessionId,
                        "analysisLatencyMs" to latencyMs,
                    ),
                )
        }
        if (update.repCompleted) {
            lastDispatchNs =
                emit(
                type = "repCompleted",
                eventId = "${current.squatSessionId}_${update.repSequence}",
                values =
                    mapOf(
                        "squatSessionId" to current.squatSessionId,
                        "sequence" to update.repSequence,
                        "detectorType" to "mediapipe",
                        "detectorVersion" to SquatDetectorConfig.VERSION,
                        "frameObservedElapsedMs" to
                            when (feature) {
                                is PoseFeatureResult.Valid -> feature.sample.timestampMs
                                is PoseFeatureResult.CalibrationCandidate ->
                                    feature.sample.timestampMs
                                is PoseFeatureResult.Invalid -> null
                            },
                        "uiEmittedElapsedMs" to elapsedMs(),
                        "analysisLatencyMs" to latencyMs,
                    ),
                )
        }
        return PoseFrameCompletion(
            stateMachineCompletedNs = stateMachineCompletedNs,
            nativeEventDispatchedNs = lastDispatchNs,
            state = update.state,
            trackingStatus = update.diagnostics.trackingStatus,
        )
    }

    private fun emitDiagnosticsIfDue(
        current: NativeSquatSession,
        update: SquatDetectorUpdate?,
        latencyMs: Long?,
        metrics: PosePipelineMetrics,
    ) {
        val debugBuild =
            previewView?.context?.applicationInfo?.flags
                ?.and(ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debugBuild) return
        val now = elapsedMs()
        if (lastDiagnosticsEmitMs != Long.MIN_VALUE &&
            now - lastDiagnosticsEmitMs < detectorConfig.diagnosticIntervalMs &&
            update?.repCompleted != true
        ) {
            return
        }
        val diagnostics = update?.diagnostics
        val activeDelegate = metrics.activeDelegate ?: delegate ?: return
        val trackingStatus =
            diagnostics?.trackingStatus ?: pipelineStatus.toTrackingStatus()
        val values =
            mapOf(
                "squatSessionId" to current.squatSessionId,
                "delegate" to activeDelegate.wireValue,
                "pipelineStatus" to pipelineStatus.wireValue,
                "poseDetected" to pipelineStatus.poseDetected,
                "trackingStatus" to trackingStatus.wireValue,
                "selectedSide" to diagnostics?.selectedSide?.wireValue,
                "leftHipConfidence" to diagnostics?.leftHipConfidence,
                "leftKneeConfidence" to diagnostics?.leftKneeConfidence,
                "leftAnkleConfidence" to diagnostics?.leftAnkleConfidence,
                "rightHipConfidence" to diagnostics?.rightHipConfidence,
                "rightKneeConfidence" to diagnostics?.rightKneeConfidence,
                "rightAnkleConfidence" to diagnostics?.rightAnkleConfidence,
                "rawKneeAngle" to diagnostics?.rawKneeAngleDeg,
                "kneeAngle" to diagnostics?.kneeAngleDeg,
                "normalizedHipDrop" to diagnostics?.normalizedHipDrop,
                "kneeAngularVelocity" to diagnostics?.kneeAngularVelocity,
                "hipVerticalVelocity" to diagnostics?.hipVerticalVelocity,
                "state" to (update?.state ?: machine.state).wireValue,
                "previousState" to diagnostics?.previousState?.wireValue,
                "lastTransitionReason" to diagnostics?.lastTransitionReason,
                "latestRejectReason" to diagnostics?.latestRejectReason,
                "lastResetReason" to diagnostics?.lastResetReason,
                "frameDtMs" to diagnostics?.frameDtMs,
                "validPoseAgeMs" to diagnostics?.validPoseAgeMs,
                "effectiveValidPoseFps" to (diagnostics?.effectiveValidPoseFps ?: 0.0),
                "calibrationSampleCount" to (diagnostics?.calibrationSampleCount ?: 0),
                "calibrationStatus" to (diagnostics?.calibrationStatus ?: "waitingForStanding"),
                "strongStandingCandidateCount" to
                    (diagnostics?.strongStandingCandidateCount ?: 0),
                "provisionalStandingAngle" to diagnostics?.provisionalStandingAngleDeg,
                "calibrationMedianAngle" to diagnostics?.calibrationMedianAngleDeg,
                "calibrationAngleRange" to diagnostics?.calibrationAngleRangeDeg,
                "calibrationWindowAgeMs" to diagnostics?.calibrationWindowAgeMs,
                "calibrationTimeoutMs" to
                    (diagnostics?.calibrationTimeoutMs ?:
                        detectorConfig.calibrationTimeoutMs(runtimeEnvironment.isEmulator)),
                "calibrationQualityPath" to diagnostics?.calibrationQualityPath?.wireValue,
                "lastCalibrationRejectReason" to diagnostics?.lastCalibrationRejectReason,
                "candidateBufferPreserved" to
                    (diagnostics?.candidateBufferPreserved ?: false),
                "autoCalibratedOnDescent" to
                    (diagnostics?.autoCalibratedOnDescent ?: false),
                "standingBaselineSource" to diagnostics?.standingBaselineSource,
                "bottomReached" to (diagnostics?.bottomReached ?: false),
                "standingConfirmationDurationMs" to
                    (diagnostics?.standingConfirmationDurationMs ?: 0),
                "bottomConfirmationDurationMs" to
                    (diagnostics?.bottomConfirmationDurationMs ?: 0),
                "returnStandingDurationMs" to
                    (diagnostics?.returnStandingDurationMs ?: 0),
                "currentRepDurationMs" to diagnostics?.currentRepDurationMs,
                "calibratedStandingKneeAngle" to
                    diagnostics?.calibratedStandingKneeAngleDeg,
                "standingThresholdDeg" to
                    (diagnostics?.standingThresholdDeg ?:
                        detectorConfig.thresholdsFor(180.0).standingEnterAngle),
                "descendingThresholdDeg" to
                    (diagnostics?.descendingThresholdDeg ?:
                        detectorConfig.thresholdsFor(180.0).descendingStartAngle),
                "bottomThresholdDeg" to
                    (diagnostics?.bottomThresholdDeg ?:
                        detectorConfig.thresholdsFor(180.0).bottomAngle),
                "returnStandingThresholdDeg" to
                    (diagnostics?.returnStandingThresholdDeg ?:
                        detectorConfig.thresholdsFor(180.0).returnStandingAngle),
                "minimumAttemptKneeAngle" to diagnostics?.minimumAttemptKneeAngleDeg,
                "maximumAttemptHipDrop" to diagnostics?.maximumAttemptHipDropRatio,
                "kneeBendDelta" to diagnostics?.kneeBendDeltaDeg,
                "downwardMovementObserved" to
                    (diagnostics?.downwardMovementObserved ?: false),
                "upwardMovementObserved" to
                    (diagnostics?.upwardMovementObserved ?: false),
                "bottomEvidenceScore" to (diagnostics?.bottomEvidenceScore ?: 0),
                "bottomEvidencePath" to diagnostics?.bottomEvidencePath?.wireValue,
                "attemptStartTimestampMs" to diagnostics?.attemptStartTimestampMs,
                "lastValidPoseTimestampMs" to diagnostics?.lastValidPoseTimestampMs,
                "baselineHipY" to diagnostics?.baselineHipY,
                "legScale" to diagnostics?.legScale,
                "baselineJitter" to diagnostics?.baselineJitter,
                "calibrationSelectedSide" to diagnostics?.calibrationSelectedSide?.wireValue,
                "analysisLatencyMs" to (latencyMs ?: 0),
                "acceptedReps" to (update?.repSequence ?: machine.repSequence),
                "rejectedAttempts" to (diagnostics?.rejectedAttempts ?: 0),
                "sampleCount" to metrics.sampleCount,
                "analyzerFrames" to metrics.analyzerFrames,
                "inferenceSubmitted" to metrics.inferenceSubmitted,
                "resultCallbacks" to metrics.resultCallbacks,
                "resultsWithPose" to metrics.resultsWithPose,
                "resultsWithoutPose" to metrics.resultsWithoutPose,
                "errorCallbacks" to metrics.errorCallbacks,
                "lastCallbackAgeMs" to metrics.lastCallbackAgeMs,
                "activeDelegate" to activeDelegate.wireValue,
                "lastError" to metrics.lastError,
                "analyzerInputFps" to metrics.analyzerInputFps,
                "inferenceSubmittedFps" to metrics.inferenceSubmittedFps,
                "resultCallbackFps" to metrics.resultCallbackFps,
                "validPoseFps" to metrics.validPoseFps,
                "actualAnalysisFps" to metrics.actualAnalysisFps,
                "requestedAnalysisWidth" to metrics.requestedAnalysisWidth,
                "requestedAnalysisHeight" to metrics.requestedAnalysisHeight,
                "actualAnalysisWidth" to metrics.actualAnalysisWidth,
                "actualAnalysisHeight" to metrics.actualAnalysisHeight,
                "droppedBeforePreprocessing" to metrics.droppedBeforePreprocessing,
                "rejectedAsBusy" to metrics.rejectedAsBusy,
                "convertedBitmapCount" to metrics.convertedBitmapCount,
                "rotationBitmapCount" to metrics.rotationBitmapCount,
                "resultCount" to metrics.resultCount,
                "noPoseCount" to metrics.noPoseCount,
                "preprocessingP50Ms" to metrics.preprocessingP50Ms,
                "preprocessingP95Ms" to metrics.preprocessingP95Ms,
                "inferenceP50Ms" to metrics.inferenceP50Ms,
                "inferenceP95Ms" to metrics.inferenceP95Ms,
                "nativePipelineP50Ms" to metrics.nativePipelineP50Ms,
                "nativePipelineP95Ms" to metrics.nativePipelineP95Ms,
                "diagnosticEventFps" to diagnosticEventFps(now) + 1,
            )
        if (values == lastDiagnosticsPayload && update?.repCompleted != true) return
        lastDiagnosticsEmitMs = now
        lastDiagnosticsPayload = values
        diagnosticEmitTimesMs.addLast(now)
        while (diagnosticEmitTimesMs.size > MAX_DIAGNOSTIC_EMIT_SAMPLES) {
            diagnosticEmitTimesMs.removeFirst()
        }
        emit(type = "diagnostics", values = values)
    }

    @Synchronized
    private fun onDetectorFailure(code: String) {
        val current = session ?: return
        emit(
            type = "detectorError",
            values =
                mapOf(
                    "squatSessionId" to current.squatSessionId,
                    "code" to code,
                ),
        )
    }

    private fun emit(
        type: String,
        eventId: String? = null,
        values: Map<String, Any?> = emptyMap(),
    ): Long? {
        val current = session ?: return null
        val emittedAt = elapsedMs()
        SquatEventBus.emit(
            SquatContract.versioned(
                mapOf(
                    "type" to type,
                    "eventId" to
                        (
                            eventId
                                ?: "${current.squatSessionId}_${type}_$emittedAt"
                        ),
                    "occurredAtEpochMs" to System.currentTimeMillis(),
                ) + values,
            ),
        )
        return elapsedNs()
    }

    private fun latencyP95(): Long? {
        if (latenciesMs.isEmpty()) return null
        val sorted = latenciesMs.sorted()
        val index = ((sorted.size - 1) * 0.95).toInt()
        return sorted[index]
    }

    private fun elapsedMs(): Long = SystemClock.elapsedRealtimeNanos() / 1_000_000

    private fun elapsedNs(): Long = SystemClock.elapsedRealtimeNanos()

    private fun logSquatFrame(update: SquatDetectorUpdate, metrics: PosePipelineMetrics) {
        if (!isDebugBuild()) return
        val diagnostics = update.diagnostics
        val transitionKey =
            diagnostics.lastTransitionReason?.let {
                "${update.state.wireValue}:$it:${update.repSequence}"
            }
        val reject = diagnostics.latestRejectReason?.takeIf { it.startsWith("REJECT_") }
        val rejectKey = reject?.let { "$it:${diagnostics.rejectedAttempts}" }
        val reset = diagnostics.lastResetReason
        val resetKey = reset?.let { "$it:${diagnostics.rejectedAttempts}" }
        val shouldTrace =
            update.repCompleted ||
                (transitionKey != null && transitionKey != lastLoggedTransitionKey) ||
                (rejectKey != null && rejectKey != lastLoggedRejectKey) ||
                (resetKey != null && resetKey != lastLoggedResetKey)
        if (shouldTrace) {
            lastLoggedTransitionKey = transitionKey
            Log.d(SQUAT_TRACE_TAG, SquatDebugTraceFormatter.trace(update, metrics))
        }
        if (update.repCompleted && update.repSequence > lastLoggedRepSequence) {
            lastLoggedRepSequence = update.repSequence
            val diagnostics = update.diagnostics
            Log.i(
                SQUAT_REP_TAG,
                String.format(
                    Locale.US,
                    "REP_ACCEPTED sequence=%d standing=%.1f minKnee=%.1f maxBend=%.1f evidence=%s",
                    update.repSequence,
                    diagnostics.calibratedStandingKneeAngleDeg ?: -1.0,
                    diagnostics.minimumAttemptKneeAngleDeg ?: -1.0,
                    diagnostics.kneeBendDeltaDeg ?: -1.0,
                    diagnostics.bottomEvidencePath?.wireValue ?: "NONE",
                ),
            )
        }
        if (rejectKey != null && rejectKey != lastLoggedRejectKey) {
            lastLoggedRejectKey = rejectKey
            Log.i(SQUAT_REP_TAG, reject)
        }
        if (resetKey != null && resetKey != lastLoggedResetKey) {
            lastLoggedResetKey = resetKey
            Log.i(SQUAT_REP_TAG, reset)
        }
    }

    private fun logPosePerformance(metrics: PosePipelineMetrics) {
        if (!isDebugBuild()) return
        val now = elapsedMs()
        val intervalMs = POSE_PERF_INTERVAL_MS
        if (lastPerfLogMs != Long.MIN_VALUE && now - lastPerfLogMs < intervalMs) return
        lastPerfLogMs = now
        Log.d(POSE_PERF_TAG, SquatDebugTraceFormatter.performance(metrics))
    }

    private fun isDebugBuild(): Boolean =
        previewView?.context?.applicationInfo?.flags
            ?.and(ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun resetDebugLogState() {
        lastPerfLogMs = Long.MIN_VALUE
        lastLoggedTransitionKey = null
        lastLoggedRepSequence = 0
        lastLoggedRejectKey = null
        lastLoggedResetKey = null
    }

    private fun diagnosticEventFps(nowMs: Long): Double {
        while (diagnosticEmitTimesMs.isNotEmpty() &&
            nowMs - diagnosticEmitTimesMs.first() > 1_000
        ) {
            diagnosticEmitTimesMs.removeFirst()
        }
        return diagnosticEmitTimesMs.size.toDouble()
    }

    override fun close() {
        stop(null)
        previewView = null
    }

    companion object {
        private const val MAX_LATENCY_SAMPLES = 300
        private const val MAX_DIAGNOSTIC_EMIT_SAMPLES = 8
        private const val POSE_PERF_INTERVAL_MS = 5_000L
        private const val SQUAT_TRACE_TAG = "SquatTrace"
        private const val SQUAT_REP_TAG = "SquatRep"
        private const val POSE_PERF_TAG = "PosePerf"
    }
}

private val PosePipelineStatus.poseDetected: Boolean
    get() =
        this != PosePipelineStatus.INITIALIZING &&
            this != PosePipelineStatus.AWAITING_RESULT &&
            this != PosePipelineStatus.NO_POSE &&
            this != PosePipelineStatus.FAILED

private fun PosePipelineStatus.toTrackingStatus(): PoseTrackingStatus =
    when (this) {
        PosePipelineStatus.INITIALIZING,
        PosePipelineStatus.AWAITING_RESULT,
        PosePipelineStatus.NO_POSE,
        PosePipelineStatus.FAILED,
        -> PoseTrackingStatus.NO_POSE
        PosePipelineStatus.HIP_UNAVAILABLE -> PoseTrackingStatus.HIP_UNAVAILABLE
        PosePipelineStatus.KNEE_UNAVAILABLE -> PoseTrackingStatus.KNEE_UNAVAILABLE
        PosePipelineStatus.ANKLE_UNAVAILABLE -> PoseTrackingStatus.ANKLE_UNAVAILABLE
        PosePipelineStatus.CONFIDENCE_INSUFFICIENT ->
            PoseTrackingStatus.CONFIDENCE_INSUFFICIENT
        PosePipelineStatus.VALID -> PoseTrackingStatus.VALID
    }
