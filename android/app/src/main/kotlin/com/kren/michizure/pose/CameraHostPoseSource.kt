package com.kren.michizure.pose

import android.os.SystemClock
import android.util.Log
import java.util.ArrayDeque
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

/** HOST_DEMO receives Pose and preview packets without opening CameraX. */
class CameraHostPoseSource(
    private val cameraContainer: SquatCameraContainer,
    private val onReady: (PoseDelegate) -> Unit,
    private val onStatus: (PosePipelineStatusSnapshot) -> Unit,
    private val onFrame: (PoseFrameDelivery) -> PoseFrameCompletion,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : PoseSource {
    private val healthExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable -> Thread(runnable, "pose-host-health") }
    private val httpClient = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private val stats = PosePipelineStats()
    private val resultGate = HostPoseResultGate()
    private val resultProcessor = HostPoseResultProcessor(config)
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val connecting = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val performance = HostPerformanceWindow(SystemClock.elapsedRealtime())
    private val renderListener =
        object : HostPoseRenderListener {
            override fun onDecoded(durationMs: Long) = performance.recordDecoded(durationMs)

            override fun onDisplayed(drawDurationMs: Long) =
                performance.recordDisplayed(drawDurationMs)

            override fun onDroppedBeforeDecode() = performance.recordDroppedBeforeDecode()

            override fun onDroppedBeforeDraw() = performance.recordDroppedBeforeDraw()
        }
    @Volatile private var latestPerformance = HostPerformanceSnapshot()
    @Volatile private var socket: WebSocket? = null
    @Volatile private var pipelineStatus = PosePipelineStatus.INITIALIZING

    override fun start() {
        if (!started.compareAndSet(false, true) || closed.get()) return
        stats.setDelegate(PoseDelegate.HOST)
        cameraContainer.setHostRenderListener(renderListener)
        publishStatus(PosePipelineStatus.INITIALIZING)
        connect()
        healthExecutor.scheduleAtFixedRate(
            ::healthTick,
            config.hostReconnectIntervalMs,
            config.hostReconnectIntervalMs,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun connect() {
        if (closed.get() || connected.get() || !connecting.compareAndSet(false, true)) return
        publishStatus(PosePipelineStatus.INITIALIZING)
        socket = httpClient.newWebSocket(Request.Builder().url(HOST_URL).build(), HostListener())
    }

    private inner class HostListener : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (closed.get()) {
                webSocket.close(1000, null)
                return
            }
            socket = webSocket
            connecting.set(false)
            connected.set(true)
            Log.i(TAG, "WebSocket connected")
            onReady(PoseDelegate.HOST)
            publishStatus(PosePipelineStatus.AWAITING_RESULT)
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            if (closed.get() || socket !== webSocket) return
            performance.recordReceived()
            stats.recordAnalyzerFrame(monotonicNs())
            processPacket(bytes.toByteArray())
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            Log.e(TAG, "server error: unexpected text response")
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            markDisconnected(webSocket)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "server error: websocket failure", t)
            markDisconnected(webSocket)
        }
    }

    private fun processPacket(message: ByteArray) {
        val receivedNs = monotonicNs()
        val packet =
            runCatching { HostPoseProtocol.decodePacket(message) }
                .onFailure { Log.e(TAG, "server error: malformed packet") }
                .getOrNull() ?: return
        if (closed.get() || !resultGate.accept(packet.frameId)) return

        stats.recordActualAnalysisResolution(packet.imageWidth, packet.imageHeight)
        stats.recordSubmitted(receivedNs, 0, PoseDelegate.HOST)
        val processed = resultProcessor.process(packet)
        val poseProcessedNs = monotonicNs()
        val status = PosePipelineStatus.fromTracking(processed.feature.quality.trackingStatus)
        pipelineStatus = status
        val guide = guideSide(processed.filteredPose, processed.feature)
        val offer =
            cameraContainer.offerHostFrame(
                HostDisplayFrame(
                    frameId = packet.frameId,
                    payload = packet.payload,
                    jpegOffset = packet.jpegOffset,
                    jpegLength = packet.jpegLength,
                    imageWidth = packet.imageWidth,
                    imageHeight = packet.imageHeight,
                    hip = guide?.hip,
                    knee = guide?.knee,
                    ankle = guide?.ankle,
                    pipelineStatus = status,
                ),
            )
        if (offer != LatestFrameOffer.ACCEPTED) performance.recordDroppedBeforeDecode()

        val latency =
            PoseLatencySample(
                analyzerReceivedNs = receivedNs,
                preprocessingStartedNs = receivedNs,
                inferenceSubmittedNs = receivedNs,
                inferenceCallbackNs = poseProcessedNs,
                stateMachineCompletedNs = poseProcessedNs,
                nativeEventDispatchedNs = null,
            )
        if (closed.get()) return
        val completion =
            onFrame(
                PoseFrameDelivery(
                    feature = processed.feature,
                    latency = latency,
                    metrics = stats.snapshot(poseProcessedNs),
                    delegate = PoseDelegate.HOST,
                ),
            )
        performance.recordStateMachine()
        val completed =
            latency.copy(
                stateMachineCompletedNs = completion.stateMachineCompletedNs,
                nativeEventDispatchedNs = completion.nativeEventDispatchedNs,
            )
        val valid =
            processed.feature is PoseFeatureResult.Valid ||
                processed.feature is PoseFeatureResult.CalibrationCandidate
        stats.recordResult(completed, packet.poseDetected, valid)
    }

    private fun guideSide(pose: LowerBodyPose, feature: PoseFeatureResult): LowerBodySide? {
        val selected =
            when (feature) {
                is PoseFeatureResult.Valid -> feature.sample.selectedSide
                is PoseFeatureResult.CalibrationCandidate -> feature.sample.selectedSide
                is PoseFeatureResult.Invalid -> feature.quality.selectedSide
            }
        return when (selected) {
            PoseSide.LEFT -> pose.left
            PoseSide.RIGHT -> pose.right
            null -> {
                fun score(side: LowerBodySide?): Double =
                    listOfNotNull(side?.hip, side?.knee, side?.ankle)
                        .minOfOrNull { it.confidence } ?: -1.0
                if (score(pose.left) >= score(pose.right)) pose.left else pose.right
            }
        }
    }

    private fun markDisconnected(webSocket: WebSocket) {
        if (closed.get() || socket !== webSocket) return
        if (connected.getAndSet(false)) Log.i(TAG, "WebSocket disconnected")
        connecting.set(false)
        socket = null
        resultGate.reset()
        resultProcessor.reset()
        cameraContainer.clearGuide()
        publishStatus(PosePipelineStatus.FAILED)
    }

    private fun healthTick() {
        if (closed.get()) return
        if (!connected.get()) connect()
        performance.finishWindow(SystemClock.elapsedRealtime())?.let {
            latestPerformance = it
            Log.i(
                PERF_TAG,
                "receiveFps=${format(it.receiveFps)} " +
                    "stateMachineFps=${format(it.stateMachineFps)} " +
                    "displayedFps=${format(it.displayedFps)} " +
                    "decodeP95Ms=${it.decodeP95Ms ?: "-"} " +
                    "drawP95Ms=${it.drawP95Ms ?: "-"} " +
                    "droppedBeforeDecode=${it.droppedBeforeDecode} " +
                    "droppedBeforeDraw=${it.droppedBeforeDraw}",
            )
        }
        val metrics = stats.snapshot(monotonicNs())
        cameraContainer.updateHostMetrics(
            latestPerformance.displayedFps,
            latestPerformance.stateMachineFps,
        )
        onStatus(PosePipelineStatusSnapshot(pipelineStatus, metrics))
    }

    private fun publishStatus(status: PosePipelineStatus) {
        pipelineStatus = status
        val snapshot = PosePipelineStatusSnapshot(status, stats.snapshot(monotonicNs()))
        cameraContainer.updatePipelineStatus(snapshot)
        onStatus(snapshot)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        cameraContainer.setHostRenderListener(null)
        socket?.close(1000, null)
        socket = null
        connected.set(false)
        connecting.set(false)
        cameraContainer.clearGuide()
        resultGate.reset()
        resultProcessor.reset()
        healthExecutor.shutdownNow()
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
    }

    private fun monotonicNs(): Long = SystemClock.elapsedRealtimeNanos()

    private fun format(value: Double) = String.format(java.util.Locale.US, "%.1f", value)

    private companion object {
        const val HOST_URL = "ws://10.0.2.2:8765"
        const val TAG = "HostPose"
        const val PERF_TAG = "PosePerf"
    }
}

internal data class HostPerformanceSnapshot(
    val receiveFps: Double = 0.0,
    val stateMachineFps: Double = 0.0,
    val displayedFps: Double = 0.0,
    val decodeP95Ms: Long? = null,
    val drawP95Ms: Long? = null,
    val droppedBeforeDecode: Long = 0,
    val droppedBeforeDraw: Long = 0,
)

internal class HostPerformanceWindow(
    startMs: Long,
    private val windowMs: Long = 5_000,
) {
    private var windowStartMs = startMs
    private var received = 0L
    private var stateMachine = 0L
    private var displayed = 0L
    private var droppedBeforeDecode = 0L
    private var droppedBeforeDraw = 0L
    private val decodeMs = ArrayDeque<Long>()
    private val drawMs = ArrayDeque<Long>()

    @Synchronized fun recordReceived() { received += 1 }
    @Synchronized fun recordStateMachine() { stateMachine += 1 }
    @Synchronized fun recordDecoded(durationMs: Long) { decodeMs.addLast(durationMs) }
    @Synchronized fun recordDisplayed(drawDurationMs: Long) {
        displayed += 1
        drawMs.addLast(drawDurationMs)
    }
    @Synchronized fun recordDroppedBeforeDecode() { droppedBeforeDecode += 1 }
    @Synchronized fun recordDroppedBeforeDraw() { droppedBeforeDraw += 1 }

    @Synchronized
    fun finishWindow(nowMs: Long): HostPerformanceSnapshot? {
        val durationMs = nowMs - windowStartMs
        if (durationMs < windowMs) return null
        val safeDurationMs = durationMs.coerceAtLeast(1)
        val snapshot =
            HostPerformanceSnapshot(
                receiveFps = received * 1_000.0 / safeDurationMs,
                stateMachineFps = stateMachine * 1_000.0 / safeDurationMs,
                displayedFps = displayed * 1_000.0 / safeDurationMs,
                decodeP95Ms = percentile95(decodeMs),
                drawP95Ms = percentile95(drawMs),
                droppedBeforeDecode = droppedBeforeDecode,
                droppedBeforeDraw = droppedBeforeDraw,
            )
        windowStartMs = nowMs
        received = 0
        stateMachine = 0
        displayed = 0
        droppedBeforeDecode = 0
        droppedBeforeDraw = 0
        decodeMs.clear()
        drawMs.clear()
        return snapshot
    }

    private fun percentile95(values: Collection<Long>): Long? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        return sorted[((sorted.size - 1) * 0.95).toInt()]
    }
}
