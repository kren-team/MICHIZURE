package com.kren.michizure.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.os.SystemClock
import android.util.Log
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
import androidx.core.view.doOnLayout
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

class CameraHostPoseSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val cameraContainer: SquatCameraContainer,
    private val onReady: (PoseDelegate) -> Unit,
    private val onStatus: (PosePipelineStatusSnapshot) -> Unit,
    private val onFrame: (PoseFrameDelivery) -> PoseFrameCompletion,
    private val onFailure: (String) -> Unit,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : PoseSource {
    private val analyzerExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "pose-host-frame") }
    private val healthExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable -> Thread(runnable, "pose-host-health") }
    private val httpClient = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private val frameDispatcher = AnalysisFrameDispatcher()
    private val stats = PosePipelineStats()
    private val resultGate = HostPoseResultGate()
    private val resultProcessor = HostPoseResultProcessor(config)
    private val pendingFrames = ConcurrentHashMap<Long, HostFrameMetadata>()
    private val nextFrameId = AtomicLong(0)
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val connecting = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val performance = HostPerformanceWindow()
    private var cameraProvider: ProcessCameraProvider? = null
    @Volatile private var socket: WebSocket? = null
    @Volatile private var pipelineStatus = PosePipelineStatus.INITIALIZING

    override fun start() {
        if (!started.compareAndSet(false, true) || closed.get()) return
        stats.setDelegate(PoseDelegate.HOST)
        bindCamera()
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
        val request = Request.Builder().url(HOST_URL).build()
        socket = httpClient.newWebSocket(request, HostSocketListener())
    }

    private inner class HostSocketListener : WebSocketListener() {
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

        override fun onMessage(webSocket: WebSocket, text: String) {
            analyzerExecutor.execute { handleResult(text) }
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            Log.e(TAG, "server error: unexpected binary response")
            webSocket.cancel()
            markDisconnected(webSocket, "unexpected_binary_response")
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            markDisconnected(webSocket, "closed:$code")
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "server error: websocket failure", t)
            markDisconnected(webSocket, "connection_failure")
        }
    }

    private fun markDisconnected(webSocket: WebSocket, reason: String) {
        if (closed.get()) return
        if (socket !== webSocket) return
        if (connected.getAndSet(false)) Log.i(TAG, "WebSocket disconnected")
        connecting.set(false)
        socket = null
        pendingFrames.clear()
        frameDispatcher.reset()
        resultGate.reset()
        performance.recordDisconnect(reason)
        publishStatus(PosePipelineStatus.FAILED)
    }

    private fun healthTick() {
        if (closed.get()) return
        if (!connected.get()) connect()
        val snapshot = stats.snapshot(monotonicNs())
        cameraContainer.updatePipelineStatus(PosePipelineStatusSnapshot(pipelineStatus, snapshot))
        onStatus(PosePipelineStatusSnapshot(pipelineStatus, snapshot))
        performance.logIfDue(snapshot)
    }

    private fun bindCamera() {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener(
            {
                if (closed.get()) return@addListener
                runCatching {
                    future.get().also { provider ->
                        cameraProvider = provider
                        cameraContainer.previewView.post {
                            if (!closed.get()) bindUseCases(provider)
                        }
                    }
                }.onFailure {
                    Log.e(TAG, "server error: camera unavailable", it)
                    onFailure("cameraUnavailable")
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bindUseCases(provider: ProcessCameraProvider) {
        val previewView = cameraContainer.previewView
        if (!previewView.isLaidOut) {
            previewView.doOnLayout { if (!closed.get()) bindUseCases(provider) }
            return
        }
        val selector =
            CameraSelector.DEFAULT_FRONT_CAMERA.takeIf { provider.hasCamera(it) }
                ?: CameraSelector.DEFAULT_BACK_CAMERA.takeIf { provider.hasCamera(it) }
                ?: error("No camera is available")
        val previewSize = Size(config.hostPreviewWidth, config.hostPreviewHeight)
        val preview =
            Preview.Builder()
                .setResolutionSelector(resolutionSelector(previewSize))
                .build()
                .also { it.surfaceProvider = previewView.surfaceProvider }
        val analysisSize = Size(config.requestedAnalysisWidth, config.requestedAnalysisHeight)
        stats.recordRequestedAnalysisResolution(analysisSize.width, analysisSize.height)
        val analysis =
            ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector(analysisSize))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { it.setAnalyzer(analyzerExecutor, ::analyze) }
        val viewPort = previewView.viewPort ?: error("Preview viewport is not ready")
        val useCases =
            UseCaseGroup.Builder()
                .setViewPort(viewPort)
                .addUseCase(preview)
                .addUseCase(analysis)
                .build()
        provider.unbindAll()
        provider.bindToLifecycle(lifecycleOwner, selector, useCases)
    }

    private fun resolutionSelector(size: Size): ResolutionSelector =
        ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(
                    size,
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                ),
            )
            .build()

    private fun analyze(imageProxy: ImageProxy) {
        val receivedNs = monotonicNs()
        stats.recordActualAnalysisResolution(imageProxy.width, imageProxy.height)
        stats.recordAnalyzerFrame(receivedNs)
        if (!connected.get()) {
            stats.recordDroppedBeforePreprocessing()
            performance.recordDrop()
            imageProxy.close()
            return
        }
        frameDispatcher.dispatch(
            nowNs = receivedNs,
            frameTimestampNs = imageProxy.imageInfo.timestamp,
            targetFps = config.targetHostAnalysisFps,
            closeFrame = imageProxy::close,
            onRejected = { decision ->
                performance.recordDrop()
                if (decision == AnalysisFrameDecision.BUSY) {
                    stats.recordRejectedAsBusy()
                } else {
                    stats.recordDroppedBeforePreprocessing()
                }
            },
        ) {
            runCatching { convertAndSend(imageProxy, receivedNs) }
                .onFailure { Log.e(TAG, "server error: frame send failed", it) }
                .getOrDefault(false)
        }
    }

    private fun convertAndSend(imageProxy: ImageProxy, analyzerReceivedNs: Long): Boolean {
        if (!connected.get()) return false
        require(imageProxy.format == PixelFormat.RGBA_8888)
        val preprocessingStartedNs = monotonicNs()
        val sourceTransform =
            ImageProxyTransformFactory().apply {
                isUsingCropRect = false
                isUsingRotationDegrees = true
            }.getOutputTransform(imageProxy)
        val source = imageProxy.toBitmap()
        stats.recordConvertedBitmap()
        val jpeg =
            try {
                ByteArrayOutputStream().use { output ->
                    check(source.compress(Bitmap.CompressFormat.JPEG, config.hostJpegQuality, output))
                    output.toByteArray()
                }
            } finally {
                source.recycle()
            }
        val submittedNs = monotonicNs()
        val frameId = nextFrameId.incrementAndGet()
        val timestampMs = imageProxy.imageInfo.timestamp / NANOS_PER_MILLISECOND
        val metadata =
            HostFrameMetadata(
                frameId = frameId,
                analyzerReceivedNs = analyzerReceivedNs,
                preprocessingStartedNs = preprocessingStartedNs,
                submittedNs = submittedNs,
                sourceTransform = sourceTransform,
            )
        pendingFrames[frameId] = metadata
        stats.recordSubmitted(
            timestampNs = submittedNs,
            preprocessingDurationMs =
                (submittedNs - preprocessingStartedNs) / NANOS_PER_MILLISECOND,
            delegate = PoseDelegate.HOST,
        )
        val message =
            HostPoseProtocol.encodeFrame(
                HostPoseFrameHeader(
                    frameId = frameId,
                    timestampMs = timestampMs,
                    imageWidth = imageProxy.width,
                    imageHeight = imageProxy.height,
                    rotationDegrees = imageProxy.imageInfo.rotationDegrees,
                ),
                jpeg,
            )
        val sent = socket?.send(message.toByteString()) == true
        if (!sent) pendingFrames.remove(frameId)
        return sent
    }

    private fun handleResult(text: String) {
        val callbackNs = monotonicNs()
        val result =
            runCatching { HostPoseProtocol.decodeResult(text) }
                .onFailure {
                    Log.e(TAG, "server error: malformed result", it)
                    socket?.let { webSocket ->
                        webSocket.cancel()
                        markDisconnected(webSocket, "malformed_result")
                    }
                }.getOrNull() ?: return
        val frame = pendingFrames.remove(result.frameId) ?: return
        frameDispatcher.completeInference()
        if (closed.get() || !resultGate.accept(result.frameId)) return
        val processed = resultProcessor.process(result)
        val status = PosePipelineStatus.fromTracking(processed.feature.quality.trackingStatus)
        pipelineStatus = status
        val latency =
            PoseLatencySample(
                analyzerReceivedNs = frame.analyzerReceivedNs,
                preprocessingStartedNs = frame.preprocessingStartedNs,
                inferenceSubmittedNs = frame.submittedNs,
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
        val guideSide = guideSide(processed.filteredPose, processed.feature)
        cameraContainer.updateGuide(
            SquatGuideFrame(
                timestampMs = result.timestampMs,
                sourceTransform = frame.sourceTransform,
                hip = guideSide?.hip,
                knee = guideSide?.knee,
                ankle = guideSide?.ankle,
                pipelineStatus = status,
                state = completion.state,
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
        stats.recordResult(completed, processed.pose.poseDetected, valid)
        performance.recordResult(completed.inferenceMs, result.inferenceMs)
        publishStatus(status)
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
        cameraProvider?.unbindAll()
        cameraProvider = null
        cameraContainer.clearGuide()
        pendingFrames.clear()
        frameDispatcher.reset()
        resultGate.reset()
        resultProcessor.reset()
        healthExecutor.shutdownNow()
        analyzerExecutor.shutdownNow()
        httpClient.dispatcher.executorService.shutdown()
        httpClient.connectionPool.evictAll()
    }

    private data class HostFrameMetadata(
        val frameId: Long,
        val analyzerReceivedNs: Long,
        val preprocessingStartedNs: Long,
        val submittedNs: Long,
        val sourceTransform: OutputTransform,
    )

    private class HostPerformanceWindow {
        private val roundTripsMs = ArrayDeque<Long>()
        private val inferenceMs = ArrayDeque<Long>()
        private var dropped = 0L
        private var lastLogMs = Long.MIN_VALUE

        @Synchronized fun recordDrop() { dropped += 1 }

        @Synchronized
        fun recordResult(roundTripMs: Long, hostInferenceMs: Long) {
            roundTripsMs.addLast(roundTripMs)
            inferenceMs.addLast(hostInferenceMs)
            while (roundTripsMs.size > MAX_PERF_SAMPLES) roundTripsMs.removeFirst()
            while (inferenceMs.size > MAX_PERF_SAMPLES) inferenceMs.removeFirst()
        }

        @Synchronized fun recordDisconnect(@Suppress("UNUSED_PARAMETER") reason: String) = Unit

        @Synchronized
        fun logIfDue(metrics: PosePipelineMetrics) {
            val now = SystemClock.elapsedRealtime()
            if (lastLogMs != Long.MIN_VALUE && now - lastLogMs < PERF_LOG_INTERVAL_MS) return
            lastLogMs = now
            Log.i(
                PERF_TAG,
                "sendFps=${format(metrics.inferenceSubmittedFps)} " +
                    "resultFps=${format(metrics.resultCallbackFps)} " +
                    "roundTripP95Ms=${p95(roundTripsMs) ?: "-"} " +
                    "hostInferenceP95Ms=${p95(inferenceMs) ?: "-"} " +
                    "dropped=$dropped",
            )
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
        const val MAX_PERF_SAMPLES = 180
    }
}
