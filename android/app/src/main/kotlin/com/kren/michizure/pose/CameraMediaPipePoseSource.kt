package com.kren.michizure.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.PixelFormat
import android.hardware.camera2.CameraCharacteristics
import android.os.SystemClock
import android.util.Range
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
import androidx.core.view.doOnLayout
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class CameraMediaPipePoseSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val cameraContainer: SquatCameraContainer,
    private val onReady: (PoseDelegate) -> Unit,
    private val onStatus: (PosePipelineStatusSnapshot) -> Unit,
    private val onFrame: (PoseFrameDelivery) -> PoseFrameCompletion,
    private val onFailure: (String) -> Unit,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
    private val runtimeEnvironment: AndroidRuntimeEnvironment =
        AndroidRuntimeEnvironment.current(),
) : PoseSource {
    private val previewView
        get() = cameraContainer.previewView
    private val analyzerExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "michizure-mediapipe-pose")
        }
    private val healthExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "michizure-mediapipe-health")
        }
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val runtimeFallbackStarted = AtomicBoolean(false)
    private val terminalPipelineFailure = AtomicBoolean(false)
    private val frameGate = AnalysisFrameGate()
    private val lastMediaPipeTimestampMs = AtomicLong(Long.MIN_VALUE)
    private val engineGeneration = AtomicLong(0)
    private val pendingMetadata = ConcurrentHashMap<Long, FrameMetadata>()
    private val poseFilter = LowerBodyPoseFilter(config)
    private val extractor = PoseFeatureExtractor(config)
    private val stats = PosePipelineStats()
    private val callbackWatchdog = PoseCallbackWatchdog()
    private var cameraProvider: ProcessCameraProvider? = null
    private var landmarker: PoseLandmarker? = null
    @Volatile private var delegate: PoseDelegate? = null
    @Volatile private var pipelineStatus = PosePipelineStatus.INITIALIZING

    override fun start() {
        if (!started.compareAndSet(false, true) || closed.get()) return
        analyzerExecutor.execute {
            if (closed.get()) return@execute
            val preferGpu =
                runtimeEnvironment.shouldPreferGpu(config.preferGpuDelegate)
            val initialized =
                runCatching {
                    PoseEngineInitializer(::createLandmarker)
                        .initialize(preferGpu)
                }.getOrElse {
                    stats.recordRuntimeError(ERROR_INITIALIZATION)
                    publishStatus(PosePipelineStatus.FAILED)
                    onFailure("poseLandmarkerUnavailable")
                    return@execute
                }
            if (closed.get()) {
                initialized.engine.close()
                return@execute
            }
            landmarker = initialized.engine
            delegate = initialized.delegate
            stats.setDelegate(initialized.delegate)
            onReady(initialized.delegate)
            publishStatus(PosePipelineStatus.AWAITING_RESULT)
            startHealthMonitor()
            bindCamera()
        }
    }

    private fun createLandmarker(selectedDelegate: PoseDelegate): PoseLandmarker {
        val baseOptions =
            BaseOptions.builder()
                .setModelAssetPath(SquatDetectorConfig.MODEL_ASSET)
                .setDelegate(
                    when (selectedDelegate) {
                        PoseDelegate.GPU -> Delegate.GPU
                        PoseDelegate.CPU -> Delegate.CPU
                    },
                )
                .build()
        val options =
            PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumPoses(1)
                .setOutputSegmentationMasks(false)
                .setMinPoseDetectionConfidence(config.minPoseDetectionConfidence)
                .setMinPosePresenceConfidence(config.minPosePresenceConfidence)
                .setMinTrackingConfidence(config.minPoseTrackingConfidence)
                .setResultListener(::onMediaPipeResult)
                .setErrorListener(::onMediaPipeError)
                .build()
        return PoseLandmarker.createFromOptions(context, options)
    }

    private fun bindCamera() {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener(
            {
                if (closed.get()) return@addListener
                runCatching {
                    val provider = future.get()
                    cameraProvider = provider
                    cameraContainer.previewView.post {
                        if (!closed.get()) {
                            runCatching { bindUseCases(provider) }
                                .onFailure { onFailure("cameraUnavailable") }
                        }
                    }
                }.onFailure {
                    onFailure("cameraUnavailable")
                }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bindUseCases(provider: ProcessCameraProvider) {
        if (!previewView.isLaidOut) {
            previewView.doOnLayout {
                if (!closed.get()) bindUseCases(provider)
            }
            return
        }
        val selector =
            CameraSelector.DEFAULT_FRONT_CAMERA.takeIf {
                provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            } ?: CameraSelector.DEFAULT_BACK_CAMERA.takeIf {
                provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
            } ?: error("No camera is available")

        val cameraInfo = selector.filter(provider.availableCameraInfos).firstOrNull()
        val supportedRanges =
            cameraInfo?.let { info ->
                Camera2CameraInfo.from(info)
                    .getCameraCharacteristic(
                        CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES,
                    )
                    ?.map { range -> SupportedFrameRateRange(range.lower, range.upper) }
                    .orEmpty()
            }.orEmpty()
        val selectedRange = CameraFrameRatePolicy.select(supportedRanges)
        val previewBuilder = Preview.Builder()
        selectedRange?.let {
            previewBuilder.setTargetFrameRate(Range(it.lower, it.upper))
        }
        val preview =
            previewBuilder.build()
                .also {
                it.surfaceProvider = previewView.surfaceProvider
            }
        val resolutionSelector =
            ResolutionSelector.Builder()
                .setResolutionStrategy(
                    ResolutionStrategy(
                        Size(480, 640),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                    ),
                )
                .build()
        val analysis =
            ImageAnalysis.Builder()
                .setResolutionSelector(resolutionSelector)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { useCase ->
                    useCase.setAnalyzer(analyzerExecutor, ::analyze)
                }

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

    private fun analyze(imageProxy: ImageProxy) {
        val analyzerReceivedNs = monotonicNs()
        var acquired = false
        stats.recordAnalyzerFrame(analyzerReceivedNs)
        try {
            if (closed.get() || terminalPipelineFailure.get()) return
            val selectedDelegate = delegate ?: return
            val targetFps =
                when {
                    runtimeEnvironment.isEmulator -> config.targetEmulatorAnalysisFps
                    selectedDelegate == PoseDelegate.GPU -> config.targetGpuAnalysisFps
                    else -> config.targetCpuAnalysisFps
                }
            when (frameGate.tryAcquire(analyzerReceivedNs, targetFps)) {
                AnalysisFrameDecision.THROTTLED -> {
                    stats.recordDroppedBeforePreprocessing()
                    return
                }
                AnalysisFrameDecision.BUSY -> {
                    stats.recordRejectedAsBusy()
                    return
                }
                AnalysisFrameDecision.ACCEPTED -> acquired = true
            }

            val preprocessingStartedNs = monotonicNs()
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val sourceTransform =
                ImageProxyTransformFactory().apply {
                    isUsingCropRect = false
                    isUsingRotationDegrees = true
                }.getOutputTransform(imageProxy)
            val frame =
                prepareFrame(
                    imageProxy = imageProxy,
                    rotationDegrees = rotationDegrees,
                    sourceTransform = sourceTransform,
                    analyzerReceivedNs = analyzerReceivedNs,
                    preprocessingStartedNs = preprocessingStartedNs,
                )
            cameraContainer.updateDebugThumbnail(frame.bitmap)
            val generation = engineGeneration.get()
            pendingMetadata[frame.timestampMs] =
                FrameMetadata(
                    timestampMs = frame.timestampMs,
                    generation = generation,
                    analyzerReceivedNs = frame.analyzerReceivedNs,
                    preprocessingStartedNs = frame.preprocessingStartedNs,
                    inferenceSubmittedNs = frame.inferenceSubmittedNs,
                    imageWidth = frame.imageWidth,
                    imageHeight = frame.imageHeight,
                    sourceTransform = frame.sourceTransform,
                )
            trimPendingMetadata()
            stats.recordSubmitted(
                timestampNs = frame.inferenceSubmittedNs,
                preprocessingDurationMs =
                    (frame.inferenceSubmittedNs - frame.preprocessingStartedNs) /
                        NANOS_PER_MILLISECOND,
                delegate = selectedDelegate,
            )
            try {
                requireNotNull(landmarker).detectAsync(frame.mpImage, frame.timestampMs)
            } catch (error: RuntimeException) {
                pendingMetadata.remove(frame.timestampMs)
                if (selectedDelegate == PoseDelegate.GPU) {
                    requestCpuFallback(ERROR_SUBMISSION)
                } else {
                    failPipeline(ERROR_SUBMISSION, "poseDetectionFailed")
                }
            } finally {
                // TaskRunner has synchronously packetized the MPImage when detectAsync
                // returns. The callback receives its own graph output MPImage.
                frame.close()
            }
        } catch (error: RuntimeException) {
            failPipeline(ERROR_PREPROCESSING, "poseDetectionFailed")
        } finally {
            if (acquired) frameGate.release()
            imageProxy.close()
        }
    }

    private fun prepareFrame(
        imageProxy: ImageProxy,
        rotationDegrees: Int,
        sourceTransform: OutputTransform,
        analyzerReceivedNs: Long,
        preprocessingStartedNs: Long,
    ): PendingFrame {
        require(imageProxy.format == PixelFormat.RGBA_8888)
        val plane = imageProxy.planes.single()
        RgbaPlaneLayoutValidator.validate(
            RgbaPlaneLayout(
                width = imageProxy.width,
                height = imageProxy.height,
                rowStride = plane.rowStride,
                pixelStride = plane.pixelStride,
                remainingBytes = plane.buffer.remaining(),
            ),
        )
        // CameraX owns the RGBA plane layout. toBitmap() handles row padding and
        // channel order; a tightly packed width*height*4 copy is intentionally
        // not used.
        val source = imageProxy.toBitmap()
        var prepared: Bitmap? = null
        try {
            prepared = rotate(source, rotationDegrees)
            if (prepared !== source) source.recycle()
            val mpImage = BitmapImageBuilder(prepared).build()
            val inferenceSubmittedNs = monotonicNs()
            return PendingFrame(
                timestampMs = nextMediaPipeTimestamp(inferenceSubmittedNs),
                analyzerReceivedNs = analyzerReceivedNs,
                preprocessingStartedNs = preprocessingStartedNs,
                inferenceSubmittedNs = inferenceSubmittedNs,
                imageWidth = prepared.width,
                imageHeight = prepared.height,
                sourceTransform = sourceTransform,
                bitmap = prepared,
                mpImage = mpImage,
            )
        } catch (error: RuntimeException) {
            if (prepared != null && prepared !== source && !prepared.isRecycled) {
                prepared.recycle()
            }
            if (!source.isRecycled) source.recycle()
            throw error
        }
    }

    private fun onMediaPipeResult(
        result: PoseLandmarkerResult,
        input: MPImage,
    ) {
        val inferenceCallbackNs = monotonicNs()
        val frame = takeFrameMetadata(result.timestampMs())
        try {
            if (closed.get()) {
                return
            }
            if (frame == null || frame.generation != engineGeneration.get()) return
            val pose =
                MediaPipePoseAdapter.convert(
                    MediaPipePoseResultSample(
                        timestampMs = frame.timestampMs,
                        imageWidth = frame.imageWidth,
                        imageHeight = frame.imageHeight,
                        landmarks =
                            result.landmarks().firstOrNull()?.map { landmark ->
                                MediaPipeLandmarkSample(
                                    x = landmark.x().toDouble(),
                                    y = landmark.y().toDouble(),
                                    z = landmark.z().toDouble(),
                                    visibility =
                                        landmark.visibility()
                                            .takeIf { it.isPresent }
                                            ?.get()
                                            ?.toDouble(),
                                    presence =
                                        landmark.presence()
                                            .takeIf { it.isPresent }
                                            ?.get()
                                            ?.toDouble(),
                                )
                            },
                    ),
                )
            val filteredPose = poseFilter.filter(pose)
            val filteredFeature = extractor.extract(filteredPose)
            val feature =
                when (filteredFeature) {
                    is PoseFeatureResult.Valid -> {
                        val rawAngle =
                            extractor.kneeAngleForSide(
                                pose,
                                filteredFeature.sample.selectedSide,
                            )
                        PoseFeatureResult.Valid(
                            sample =
                                filteredFeature.sample.copy(
                                    rawKneeAngleDeg =
                                        rawAngle ?: filteredFeature.sample.kneeAngleDeg,
                                ),
                            quality = filteredFeature.quality,
                        )
                    }
                    is PoseFeatureResult.Invalid -> filteredFeature
                }
            val nextPipelineStatus =
                PosePipelineStatus.fromTracking(feature.quality.trackingStatus)
            pipelineStatus = nextPipelineStatus
            val beforeStateMachine =
                PoseLatencySample(
                    analyzerReceivedNs = frame.analyzerReceivedNs,
                    preprocessingStartedNs = frame.preprocessingStartedNs,
                    inferenceSubmittedNs = frame.inferenceSubmittedNs,
                    inferenceCallbackNs = inferenceCallbackNs,
                    stateMachineCompletedNs = inferenceCallbackNs,
                    nativeEventDispatchedNs = null,
                )
            val completion =
                onFrame(
                    PoseFrameDelivery(
                        feature = feature,
                        latency = beforeStateMachine,
                        metrics = stats.snapshot(inferenceCallbackNs),
                        delegate = requireNotNull(delegate),
                    ),
                )
            val selectedSide =
                (feature as? PoseFeatureResult.Valid)?.sample?.selectedSide
                    ?: feature.quality.selectedSide
            val guideSide =
                when (selectedSide) {
                    PoseSide.LEFT -> filteredPose.left
                    PoseSide.RIGHT -> filteredPose.right
                    null -> preferredGuideSide(filteredPose)
                }
            cameraContainer.updateGuide(
                SquatGuideFrame(
                    timestampMs = frame.timestampMs,
                    sourceTransform = frame.sourceTransform,
                    hip = guideSide?.hip,
                    knee = guideSide?.knee,
                    ankle = guideSide?.ankle,
                    pipelineStatus = nextPipelineStatus,
                    state = completion.state,
                ),
            )
            val completed =
                beforeStateMachine.copy(
                    stateMachineCompletedNs = completion.stateMachineCompletedNs,
                    nativeEventDispatchedNs = completion.nativeEventDispatchedNs,
                )
            stats.recordResult(
                sample = completed,
                poseDetected = pose.poseDetected,
                validPose = feature is PoseFeatureResult.Valid,
            )
            publishStatus(nextPipelineStatus)
        } finally {
            input.close()
        }
    }

    private fun onMediaPipeError(@Suppress("UNUSED_PARAMETER") error: RuntimeException) {
        val nowNs = monotonicNs()
        pendingMetadata.clear()
        stats.recordError(nowNs, ERROR_CALLBACK)
        if (closed.get()) return
        if (delegate == PoseDelegate.GPU) {
            requestCpuFallback(ERROR_GPU_CALLBACK)
        } else {
            failPipeline(ERROR_CALLBACK, "poseDetectionFailed")
        }
    }

    private fun rotate(
        bitmap: Bitmap,
        rotationDegrees: Int,
    ): Bitmap {
        if (rotationDegrees == 0) return bitmap
        val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
    }

    private fun nextMediaPipeTimestamp(nowNs: Long): Long {
        val nowMs = nowNs / NANOS_PER_MILLISECOND
        while (true) {
            val previous = lastMediaPipeTimestampMs.get()
            val next = if (nowMs > previous) nowMs else previous + 1
            if (lastMediaPipeTimestampMs.compareAndSet(previous, next)) return next
        }
    }

    private fun startHealthMonitor() {
        healthExecutor.scheduleAtFixedRate(
            {
                if (closed.get()) return@scheduleAtFixedRate
                val metrics = stats.snapshot(monotonicNs())
                onStatus(PosePipelineStatusSnapshot(pipelineStatus, metrics))
                when (callbackWatchdog.evaluate(metrics)) {
                    PoseRuntimeRecoveryAction.NONE -> Unit
                    PoseRuntimeRecoveryAction.FALLBACK_TO_CPU ->
                        requestCpuFallback(ERROR_GPU_CALLBACK_TIMEOUT)
                    PoseRuntimeRecoveryAction.FAIL_CPU -> {
                        failPipeline(
                            ERROR_CPU_CALLBACK_TIMEOUT,
                            "poseDetectionFailed",
                        )
                    }
                }
            },
            HEALTH_CHECK_INTERVAL_MS,
            HEALTH_CHECK_INTERVAL_MS,
            TimeUnit.MILLISECONDS,
        )
    }

    private fun requestCpuFallback(reason: String) {
        if (!runtimeFallbackStarted.compareAndSet(false, true)) return
        analyzerExecutor.execute {
            if (closed.get() || delegate != PoseDelegate.GPU) return@execute
            stats.recordRuntimeError(reason)
            pipelineStatus = PosePipelineStatus.INITIALIZING
            publishStatus(PosePipelineStatus.INITIALIZING)
            engineGeneration.incrementAndGet()
            pendingMetadata.clear()
            frameGate.reset()
            runCatching { landmarker?.close() }
            landmarker = null
            val cpuEngine =
                runCatching { createLandmarker(PoseDelegate.CPU) }
                    .getOrElse {
                        stats.recordRuntimeError(ERROR_CPU_INITIALIZATION)
                        publishStatus(PosePipelineStatus.FAILED)
                        onFailure("poseLandmarkerUnavailable")
                        return@execute
                    }
            if (closed.get()) {
                cpuEngine.close()
                return@execute
            }
            landmarker = cpuEngine
            delegate = PoseDelegate.CPU
            stats.setDelegate(PoseDelegate.CPU)
            callbackWatchdog.reset()
            poseFilter.reset()
            extractor.reset()
            onReady(PoseDelegate.CPU)
            publishStatus(PosePipelineStatus.AWAITING_RESULT)
        }
    }

    private fun failPipeline(
        diagnosticCode: String,
        failureCode: String,
    ) {
        if (!terminalPipelineFailure.compareAndSet(false, true)) return
        stats.recordRuntimeError(diagnosticCode)
        engineGeneration.incrementAndGet()
        pendingMetadata.clear()
        frameGate.reset()
        publishStatus(PosePipelineStatus.FAILED)
        onFailure(failureCode)
        runCatching {
            analyzerExecutor.execute {
                runCatching { landmarker?.close() }
                landmarker = null
                poseFilter.reset()
                extractor.reset()
            }
        }
    }

    private fun publishStatus(status: PosePipelineStatus) {
        pipelineStatus = status
        val snapshot = PosePipelineStatusSnapshot(status, stats.snapshot(monotonicNs()))
        cameraContainer.updatePipelineStatus(snapshot)
        onStatus(snapshot)
    }

    private fun takeFrameMetadata(timestampMs: Long): FrameMetadata? {
        val matching = pendingMetadata.remove(timestampMs)
        pendingMetadata.keys.removeIf { it <= timestampMs }
        return matching
    }

    private fun trimPendingMetadata() {
        if (pendingMetadata.size <= MAX_PENDING_METADATA) return
        pendingMetadata.keys.sorted()
            .take(pendingMetadata.size - MAX_PENDING_METADATA)
            .forEach(pendingMetadata::remove)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        cameraProvider?.unbindAll()
        cameraProvider = null
        cameraContainer.clearGuide()
        frameGate.reset()
        healthExecutor.shutdownNow()
        runCatching {
            analyzerExecutor.execute {
                engineGeneration.incrementAndGet()
                landmarker?.close()
                landmarker = null
                pendingMetadata.clear()
                poseFilter.reset()
                extractor.reset()
                stats.reset()
            }
        }.onFailure {
            pendingMetadata.clear()
        }
        analyzerExecutor.shutdown()
    }

    private data class PendingFrame(
        val timestampMs: Long,
        val analyzerReceivedNs: Long,
        val preprocessingStartedNs: Long,
        val inferenceSubmittedNs: Long,
        val imageWidth: Int,
        val imageHeight: Int,
        val sourceTransform: OutputTransform,
        val bitmap: Bitmap,
        val mpImage: MPImage,
    ) : AutoCloseable {
        private val closed = AtomicBoolean(false)

        override fun close() {
            if (!closed.compareAndSet(false, true)) return
            mpImage.close()
            bitmap.recycle()
        }
    }

    private data class FrameMetadata(
        val timestampMs: Long,
        val generation: Long,
        val analyzerReceivedNs: Long,
        val preprocessingStartedNs: Long,
        val inferenceSubmittedNs: Long,
        val imageWidth: Int,
        val imageHeight: Int,
        val sourceTransform: OutputTransform,
    )

    private fun monotonicNs(): Long = SystemClock.elapsedRealtimeNanos()

    private fun preferredGuideSide(pose: LowerBodyPose): LowerBodySide? {
        fun score(side: LowerBodySide?): Double =
            listOfNotNull(
                side?.hip?.confidence,
                side?.knee?.confidence,
                side?.ankle?.confidence,
            ).minOrNull() ?: -1.0
        return if (score(pose.left) >= score(pose.right)) pose.left else pose.right
    }

    private companion object {
        const val NANOS_PER_MILLISECOND = 1_000_000L
        const val HEALTH_CHECK_INTERVAL_MS = 250L
        const val MAX_PENDING_METADATA = 24
        const val ERROR_INITIALIZATION = "landmarker_initialization"
        const val ERROR_PREPROCESSING = "rgba_preprocessing"
        const val ERROR_SUBMISSION = "inference_submission"
        const val ERROR_CALLBACK = "inference_callback"
        const val ERROR_GPU_CALLBACK = "gpu_callback_error"
        const val ERROR_GPU_CALLBACK_TIMEOUT = "gpu_callback_timeout"
        const val ERROR_CPU_CALLBACK_TIMEOUT = "cpu_callback_timeout"
        const val ERROR_CPU_INITIALIZATION = "cpu_initialization"
    }
}
