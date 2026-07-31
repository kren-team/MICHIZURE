package com.kren.michizure.pose

import android.graphics.BitmapFactory
import android.os.SystemClock
import android.util.Log
import java.util.ArrayDeque
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

/** HOST_DEMO receives already-inferred preview packets and never opens CameraX. */
class CameraHostPoseSource(
    private val cameraContainer: SquatCameraContainer,
    private val onReady: (PoseDelegate) -> Unit,
    private val onStatus: (PosePipelineStatusSnapshot) -> Unit,
    private val onFrame: (PoseFrameDelivery) -> PoseFrameCompletion,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : PoseSource {
    private val decodeExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "pose-host-decode") }
    private val healthExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable -> Thread(runnable, "pose-host-health") }
    private val httpClient = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private val stats = PosePipelineStats()
    private val resultGate = HostPoseResultGate()
    private val resultProcessor = HostPoseResultProcessor(config)
    private val pendingPacket = AtomicReference<ByteString?>(null)
    private val drainScheduled = AtomicBoolean(false)
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val connecting = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val performance = HostReceivePerformance()
    @Volatile private var socket: WebSocket? = null
    @Volatile private var pipelineStatus = PosePipelineStatus.INITIALIZING

    override fun start() {
        if (!started.compareAndSet(false, true) || closed.get()) return
        stats.setDelegate(PoseDelegate.HOST)
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
            if (pendingPacket.getAndSet(bytes) != null) performance.recordDroppedDisplay()
            scheduleDrain()
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

    private fun scheduleDrain() {
        if (!drainScheduled.compareAndSet(false, true)) return
        decodeExecutor.execute {
            try {
                while (!closed.get()) {
                    val message = pendingPacket.getAndSet(null) ?: break
                    processPacket(message)
                }
            } finally {
                drainScheduled.set(false)
                if (pendingPacket.get() != null) scheduleDrain()
            }
        }
    }

    private fun processPacket(message: ByteString) {
        val receivedNs = monotonicNs()
        val packet =
            runCatching { HostPoseProtocol.decodePacket(message.toByteArray()) }
                .onFailure { Log.e(TAG, "server error: malformed packet") }
                .getOrNull() ?: return
        if (!resultGate.accept(packet.frameId)) {
            performance.recordDroppedDisplay()
            return
        }
        val decodeStartedNs = monotonicNs()
        val bitmap =
            BitmapFactory.decodeByteArray(packet.jpeg, 0, packet.jpeg.size)
                ?: run {
                    Log.e(TAG, "server error: invalid JPEG")
                    return
                }
        if (bitmap.width != packet.imageWidth || bitmap.height != packet.imageHeight) {
            bitmap.recycle()
            Log.e(TAG, "server error: JPEG dimensions do not match header")
            return
        }
        val callbackNs = monotonicNs()
        val decodeMs = (callbackNs - decodeStartedNs) / NANOS_PER_MILLISECOND
        performance.recordDecoded(decodeMs)
        stats.recordActualAnalysisResolution(packet.imageWidth, packet.imageHeight)
        stats.recordSubmitted(receivedNs, 0, PoseDelegate.HOST)

        val processed = resultProcessor.process(packet)
        val status = PosePipelineStatus.fromTracking(processed.feature.quality.trackingStatus)
        pipelineStatus = status
        val latency =
            PoseLatencySample(
                analyzerReceivedNs = receivedNs,
                preprocessingStartedNs = decodeStartedNs,
                inferenceSubmittedNs = decodeStartedNs,
                inferenceCallbackNs = callbackNs,
                stateMachineCompletedNs = callbackNs,
                nativeEventDispatchedNs = null,
            )
        val completion =
            onFrame(
                PoseFrameDelivery(
                    feature = processed.feature,
                    latency = latency,
                    metrics = stats.snapshot(callbackNs),
                    delegate = PoseDelegate.HOST,
                ),
            )
        val completed =
            latency.copy(
                stateMachineCompletedNs = completion.stateMachineCompletedNs,
                nativeEventDispatchedNs = completion.nativeEventDispatchedNs,
            )
        val valid =
            processed.feature is PoseFeatureResult.Valid ||
                processed.feature is PoseFeatureResult.CalibrationCandidate
        stats.recordResult(completed, packet.poseDetected, valid)
        performance.recordPose(packet.poseDetected)
        val guide = guideSide(processed.filteredPose, processed.feature)
        cameraContainer.updateHostFrame(
            HostSquatGuideFrame(
                frameId = packet.frameId,
                bitmap = bitmap,
                imageWidth = packet.imageWidth,
                imageHeight = packet.imageHeight,
                hip = guide?.hip,
                knee = guide?.knee,
                ankle = guide?.ankle,
                pipelineStatus = status,
                state = completion.state,
            ),
            onDisplayed = performance::recordDisplayed,
            onDropped = performance::recordDroppedDisplay,
        )
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
        pendingPacket.getAndSet(null)
        resultGate.reset()
        resultProcessor.reset()
        cameraContainer.clearGuide()
        publishStatus(PosePipelineStatus.FAILED)
    }

    private fun healthTick() {
        if (closed.get()) return
        if (!connected.get()) connect()
        val metrics = stats.snapshot(monotonicNs())
        val snapshot = performance.snapshot()
        cameraContainer.updateHostMetrics(snapshot.displayedFps, snapshot.poseFps)
        onStatus(PosePipelineStatusSnapshot(pipelineStatus, metrics))
        performance.logIfDue()
    }

    private fun publishStatus(status: PosePipelineStatus) {
        pipelineStatus = status
        val snapshot = PosePipelineStatusSnapshot(status, stats.snapshot(monotonicNs()))
        cameraContainer.updatePipelineStatus(snapshot)
        onStatus(snapshot)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        socket?.close(1000, null)
        socket = null
        connected.set(false)
        connecting.set(false)
        pendingPacket.getAndSet(null)
        cameraContainer.clearGuide()
        resultGate.reset()
        resultProcessor.reset()
        healthExecutor.shutdownNow()
        decodeExecutor.shutdownNow()
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
    }

    private data class HostReceiveSnapshot(val displayedFps: Double, val poseFps: Double)

    private class HostReceivePerformance {
        private val receiveTimesMs = ArrayDeque<Long>()
        private val displayTimesMs = ArrayDeque<Long>()
        private val poseTimesMs = ArrayDeque<Long>()
        private val decodeMs = ArrayDeque<Long>()
        private var droppedDisplay = 0L
        private var lastLogMs = Long.MIN_VALUE

        @Synchronized fun recordReceived() = add(receiveTimesMs, SystemClock.elapsedRealtime())
        @Synchronized fun recordDisplayed() = add(displayTimesMs, SystemClock.elapsedRealtime())
        @Synchronized fun recordPose(detected: Boolean) {
            if (detected) add(poseTimesMs, SystemClock.elapsedRealtime())
        }
        @Synchronized fun recordDecoded(durationMs: Long) = add(decodeMs, durationMs)
        @Synchronized fun recordDroppedDisplay() { droppedDisplay += 1 }

        @Synchronized
        fun snapshot(): HostReceiveSnapshot {
            val now = SystemClock.elapsedRealtime()
            return HostReceiveSnapshot(fps(displayTimesMs, now), fps(poseTimesMs, now))
        }

        @Synchronized
        fun logIfDue() {
            val now = SystemClock.elapsedRealtime()
            if (lastLogMs != Long.MIN_VALUE && now - lastLogMs < PERF_LOG_INTERVAL_MS) return
            lastLogMs = now
            Log.i(
                PERF_TAG,
                "receiveFps=${format(fps(receiveTimesMs, now))} " +
                    "displayedFps=${format(fps(displayTimesMs, now))} " +
                    "poseFps=${format(fps(poseTimesMs, now))} " +
                    "decodeP95Ms=${p95(decodeMs) ?: "-"} " +
                    "droppedDisplay=$droppedDisplay",
            )
        }

        private fun add(values: ArrayDeque<Long>, value: Long) {
            values.addLast(value)
            while (values.size > MAX_SAMPLES) values.removeFirst()
        }

        private fun fps(values: ArrayDeque<Long>, now: Long): Double {
            while (values.isNotEmpty() && now - values.first() > FPS_WINDOW_MS) {
                values.removeFirst()
            }
            if (values.size < 2) return 0.0
            val duration = values.last() - values.first()
            return if (duration <= 0) 0.0 else (values.size - 1) * 1_000.0 / duration
        }

        private fun p95(values: Collection<Long>): Long? {
            if (values.isEmpty()) return null
            val sorted = values.sorted()
            return sorted[((sorted.size - 1) * 0.95).toInt()]
        }

        private fun format(value: Double) = String.format(java.util.Locale.US, "%.1f", value)
    }

    private fun monotonicNs(): Long = SystemClock.elapsedRealtimeNanos()

    private companion object {
        const val HOST_URL = "ws://10.0.2.2:8765"
        const val TAG = "HostPose"
        const val PERF_TAG = "PosePerf"
        const val NANOS_PER_MILLISECOND = 1_000_000L
        const val PERF_LOG_INTERVAL_MS = 5_000L
        const val FPS_WINDOW_MS = 5_000L
        const val MAX_SAMPLES = 180
    }
}
