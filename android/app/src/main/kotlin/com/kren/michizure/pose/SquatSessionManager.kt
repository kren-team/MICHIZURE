package com.kren.michizure.pose

import android.os.SystemClock
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import java.util.ArrayDeque

data class NativeSquatSession(
    val squatSessionId: String,
    val debtId: String,
)

class SquatSessionManager(
    private val lifecycleOwner: LifecycleOwner,
    private val sourceFactory: (
        PreviewView,
        LifecycleOwner,
        (PoseFeatureResult, Long) -> Unit,
        () -> Unit,
    ) -> PoseSource = { view, owner, onFrame, onFailure ->
        CameraMlKitPoseSource(
            context = view.context.applicationContext,
            lifecycleOwner = owner,
            previewView = view,
            onFrame = onFrame,
            onFailure = onFailure,
        )
    },
) : AutoCloseable {
    private var session: NativeSquatSession? = null
    private var previewView: PreviewView? = null
    private var source: PoseSource? = null
    private var machine = SquatStateMachine()
    private var lastState: SquatState? = null
    private var lastWarning: PoseQualityWarning? = null
    private val latenciesMs = ArrayDeque<Long>()

    @Synchronized
    fun attachPreview(view: PreviewView) {
        previewView = view
        startSourceIfReady()
    }

    @Synchronized
    fun detachPreview(view: PreviewView) {
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
        machine = SquatStateMachine()
        lastState = null
        lastWarning = null
        latenciesMs.clear()
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
        val currentSession = session ?: return
        val view = previewView ?: return
        if (source != null) return
        source =
            sourceFactory(
                view,
                lifecycleOwner,
                ::onFrame,
                ::onDetectorFailure,
            ).also { it.start() }
        emit(
            type = "detectorReady",
            values =
                mapOf(
                    "detectorType" to "mlkit",
                    "detectorVersion" to SquatDetectorConfig.VERSION,
                    "squatSessionId" to currentSession.squatSessionId,
                ),
        )
    }

    @Synchronized
    private fun onFrame(
        feature: PoseFeatureResult,
        latencyMs: Long,
    ) {
        val current = session ?: return
        latenciesMs.addLast(latencyMs)
        while (latenciesMs.size > MAX_LATENCY_SAMPLES) latenciesMs.removeFirst()
        val update = machine.process(feature)
        if (update.state != lastState) {
            lastState = update.state
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
            emit(
                type = "repCompleted",
                eventId = "${current.squatSessionId}_${update.repSequence}",
                values =
                    mapOf(
                        "squatSessionId" to current.squatSessionId,
                        "sequence" to update.repSequence,
                        "detectorType" to "mlkit",
                        "detectorVersion" to SquatDetectorConfig.VERSION,
                        "frameObservedElapsedMs" to
                            (feature as? PoseFeatureResult.Valid)?.sample?.timestampMs,
                        "uiEmittedElapsedMs" to elapsedMs(),
                        "analysisLatencyMs" to latencyMs,
                    ),
            )
        }
    }

    @Synchronized
    private fun onDetectorFailure() {
        val current = session ?: return
        emit(
            type = "detectorError",
            values =
                mapOf(
                    "squatSessionId" to current.squatSessionId,
                    "code" to "poseDetectionFailed",
                ),
        )
    }

    private fun emit(
        type: String,
        eventId: String? = null,
        values: Map<String, Any?> = emptyMap(),
    ) {
        val current = session ?: return
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
    }

    private fun latencyP95(): Long? {
        if (latenciesMs.isEmpty()) return null
        val sorted = latenciesMs.sorted()
        val index = ((sorted.size - 1) * 0.95).toInt()
        return sorted[index]
    }

    private fun elapsedMs(): Long = SystemClock.elapsedRealtimeNanos() / 1_000_000

    override fun close() {
        stop(null)
        previewView = null
    }

    companion object {
        private const val MAX_LATENCY_SAMPLES = 300
    }
}
