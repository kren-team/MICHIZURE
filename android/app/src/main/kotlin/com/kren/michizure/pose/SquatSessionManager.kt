package com.kren.michizure.pose

import android.content.pm.ApplicationInfo
import android.os.SystemClock
import androidx.lifecycle.LifecycleOwner
import java.util.ArrayDeque

data class NativeSquatSession(
    val squatSessionId: String,
    val debtId: String,
)

class SquatSessionManager(
    private val lifecycleOwner: LifecycleOwner,
    private val sourceFactory: (
        SquatCameraContainer,
        LifecycleOwner,
        (PoseDelegate) -> Unit,
        (PoseFrameDelivery) -> PoseFrameCompletion,
        (String) -> Unit,
    ) -> PoseSource = { container, owner, onReady, onFrame, onFailure ->
        CameraMediaPipePoseSource(
            context = container.context.applicationContext,
            lifecycleOwner = owner,
            cameraContainer = container,
            onReady = onReady,
            onFrame = onFrame,
            onFailure = onFailure,
        )
    },
) : AutoCloseable {
    private val detectorConfig = SquatDetectorConfig()
    private var session: NativeSquatSession? = null
    private var cameraContainer: SquatCameraContainer? = null
    private var source: PoseSource? = null
    private var machine = SquatStateMachine(detectorConfig)
    private var lastState: SquatState? = null
    private var lastWarning: PoseQualityWarning? = null
    private var lastDiagnosticsEmitMs = Long.MIN_VALUE
    private var lastDiagnosticsPayload: Map<String, Any?>? = null
    private val diagnosticEmitTimesMs = ArrayDeque<Long>()
    private val latenciesMs = ArrayDeque<Long>()
    private var delegate: PoseDelegate? = null

    @Synchronized
    fun attachPreview(container: SquatCameraContainer) {
        cameraContainer = container
        startSourceIfReady()
    }

    @Synchronized
    fun detachPreview(container: SquatCameraContainer) {
        if (cameraContainer !== container) return
        cameraContainer = null
        source?.close()
        source = null
        container.clearGuide()
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
        machine = SquatStateMachine(detectorConfig)
        lastState = null
        lastWarning = null
        latenciesMs.clear()
        diagnosticEmitTimesMs.clear()
        lastDiagnosticsEmitMs = Long.MIN_VALUE
        lastDiagnosticsPayload = null
        delegate = null
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
        latenciesMs.clear()
        diagnosticEmitTimesMs.clear()
        lastDiagnosticsEmitMs = Long.MIN_VALUE
        lastDiagnosticsPayload = null
        delegate = null
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
                "repSequence" to machine.repSequence,
                "latencyP95Ms" to latencyP95(),
            ),
        )
    }

    @Synchronized
    private fun startSourceIfReady() {
        session ?: return
        val container = cameraContainer ?: return
        if (source != null) return
        source =
            sourceFactory(
                container,
                lifecycleOwner,
                ::onDetectorReady,
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
    private fun onFrame(delivery: PoseFrameDelivery): PoseFrameCompletion {
        val current =
            session
                ?: return PoseFrameCompletion(
                    stateMachineCompletedNs = elapsedNs(),
                    nativeEventDispatchedNs = null,
                )
        val feature = delivery.feature
        val update = machine.process(feature)
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
                            (feature as? PoseFeatureResult.Valid)?.sample?.timestampMs,
                        "uiEmittedElapsedMs" to elapsedMs(),
                        "analysisLatencyMs" to latencyMs,
                    ),
                )
        }
        return PoseFrameCompletion(
            stateMachineCompletedNs = stateMachineCompletedNs,
            nativeEventDispatchedNs = lastDispatchNs,
            state = update.state,
            selectedSide = update.diagnostics.selectedSide,
            trackingStatus = update.diagnostics.trackingStatus,
        )
    }

    private fun emitDiagnosticsIfDue(
        current: NativeSquatSession,
        update: SquatDetectorUpdate,
        latencyMs: Long,
        metrics: PosePipelineMetrics,
    ) {
        val debugBuild =
            cameraContainer?.context?.applicationInfo?.flags
                ?.and(ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debugBuild) return
        val now = elapsedMs()
        if (lastDiagnosticsEmitMs != Long.MIN_VALUE &&
            now - lastDiagnosticsEmitMs < detectorConfig.diagnosticIntervalMs &&
            !update.repCompleted
        ) {
            return
        }
        val diagnostics = update.diagnostics
        val values =
            mapOf(
                "squatSessionId" to current.squatSessionId,
                "delegate" to delegate?.wireValue,
                "poseDetected" to diagnostics.poseDetected,
                "trackingStatus" to diagnostics.trackingStatus.wireValue,
                "selectedSide" to diagnostics.selectedSide?.wireValue,
                "leftHipConfidence" to diagnostics.leftHipConfidence,
                "leftKneeConfidence" to diagnostics.leftKneeConfidence,
                "leftAnkleConfidence" to diagnostics.leftAnkleConfidence,
                "rightHipConfidence" to diagnostics.rightHipConfidence,
                "rightKneeConfidence" to diagnostics.rightKneeConfidence,
                "rightAnkleConfidence" to diagnostics.rightAnkleConfidence,
                "normalizedVerticalGap" to diagnostics.normalizedVerticalGap,
                "normalizedHipDrop" to diagnostics.normalizedHipDrop,
                "state" to update.state.wireValue,
                "latestRejectReason" to diagnostics.latestRejectReason,
                "analysisLatencyMs" to latencyMs,
                "acceptedReps" to update.repSequence,
                "rejectedAttempts" to diagnostics.rejectedAttempts,
                "sampleCount" to metrics.sampleCount,
                "actualAnalysisFps" to metrics.actualAnalysisFps,
                "droppedBeforePreprocessing" to metrics.droppedBeforePreprocessing,
                "rejectedAsBusy" to metrics.rejectedAsBusy,
                "resultCount" to metrics.resultCount,
                "noPoseCount" to metrics.noPoseCount,
                "inferenceP50Ms" to metrics.inferenceP50Ms,
                "inferenceP95Ms" to metrics.inferenceP95Ms,
                "nativePipelineP50Ms" to metrics.nativePipelineP50Ms,
                "nativePipelineP95Ms" to metrics.nativePipelineP95Ms,
                "diagnosticEventFps" to diagnosticEventFps(now) + 1,
            )
        if (values == lastDiagnosticsPayload && !update.repCompleted) return
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
        cameraContainer = null
    }

    companion object {
        private const val MAX_LATENCY_SAMPLES = 300
        private const val MAX_DIAGNOSTIC_EMIT_SAMPLES = 8
    }
}
