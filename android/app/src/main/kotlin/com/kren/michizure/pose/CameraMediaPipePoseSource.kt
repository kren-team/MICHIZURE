package com.kren.michizure.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
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
import androidx.camera.view.transform.ImageProxyTransformFactory
import androidx.camera.view.transform.OutputTransform
import androidx.core.content.ContextCompat
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
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class CameraMediaPipePoseSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val cameraContainer: SquatCameraContainer,
    private val onReady: (PoseDelegate) -> Unit,
    private val onFrame: (PoseFrameDelivery) -> PoseFrameCompletion,
    private val onFailure: (String) -> Unit,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : PoseSource {
    private val analyzerExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "michizure-mediapipe-pose")
        }
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val frameGate = AnalysisFrameGate()
    private val lastMediaPipeTimestampMs = AtomicLong(Long.MIN_VALUE)
    private val pending = AtomicReference<PendingFrame?>()
    private val poseFilter = LowerBodyPoseFilter(config)
    private val extractor = PoseFeatureExtractor(config)
    private val stats = PosePipelineStats()
    private var cameraProvider: ProcessCameraProvider? = null
    private var landmarker: PoseLandmarker? = null
    private var delegate: PoseDelegate? = null

    override fun start() {
        if (!started.compareAndSet(false, true) || closed.get()) return
        analyzerExecutor.execute {
            if (closed.get()) return@execute
            val initialized =
                runCatching {
                    PoseEngineInitializer(::createLandmarker)
                        .initialize(config.preferGpuDelegate)
                }.getOrElse {
                    onFailure("poseLandmarkerUnavailable")
                    return@execute
                }
            if (closed.get()) {
                initialized.engine.close()
                return@execute
            }
            landmarker = initialized.engine
            delegate = initialized.delegate
            onReady(initialized.delegate)
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
        val previewView = cameraContainer.previewView
        val selector =
            CameraSelector.DEFAULT_FRONT_CAMERA.takeIf {
                provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            } ?: CameraSelector.DEFAULT_BACK_CAMERA.takeIf {
                provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
            } ?: error("No camera is available")

        val preview =
            Preview.Builder()
                .setTargetFrameRate(Range(PREVIEW_MIN_FPS, PREVIEW_TARGET_FPS))
                .build()
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
        try {
            if (closed.get()) return
            val selectedDelegate = delegate ?: return
            val targetFps =
                when (selectedDelegate) {
                    PoseDelegate.GPU -> config.targetGpuAnalysisFps
                    PoseDelegate.CPU -> config.targetCpuAnalysisFps
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
                AnalysisFrameDecision.ACCEPTED -> Unit
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
                    analyzerReceivedNs = analyzerReceivedNs,
                    preprocessingStartedNs = preprocessingStartedNs,
                    sourceTransform = sourceTransform,
                )
            pending.set(frame)
            stats.recordSubmitted(frame.inferenceSubmittedNs)
            try {
                requireNotNull(landmarker).detectAsync(frame.mpImage, frame.timestampMs)
            } catch (error: RuntimeException) {
                pending.compareAndSet(frame, null)
                frame.close()
                frameGate.release()
                onFailure("poseDetectionFailed")
            }
        } catch (error: RuntimeException) {
            frameGate.release()
            onFailure("poseDetectionFailed")
        } finally {
            imageProxy.close()
        }
    }

    private fun prepareFrame(
        imageProxy: ImageProxy,
        rotationDegrees: Int,
        analyzerReceivedNs: Long,
        preprocessingStartedNs: Long,
        sourceTransform: OutputTransform,
    ): PendingFrame {
        val source =
            Bitmap.createBitmap(
                imageProxy.width,
                imageProxy.height,
                Bitmap.Config.ARGB_8888,
            )
        var prepared: Bitmap? = null
        try {
            imageProxy.planes[0].buffer.rewind()
            source.copyPixelsFromBuffer(imageProxy.planes[0].buffer)
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
        @Suppress("UNUSED_PARAMETER") input: MPImage,
    ) {
        val frame = pending.getAndSet(null) ?: return
        try {
            if (closed.get() || result.timestampMs() != frame.timestampMs) return
            val inferenceCallbackNs = monotonicNs()
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
            val feature = extractor.extract(filteredPose)
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
                        metrics = stats.snapshot(),
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
                    trackingStatus = completion.trackingStatus,
                    state = completion.state,
                ),
            )
            val completed =
                beforeStateMachine.copy(
                    stateMachineCompletedNs = completion.stateMachineCompletedNs,
                    nativeEventDispatchedNs = completion.nativeEventDispatchedNs,
                )
            stats.recordResult(completed, pose.poseDetected)
        } finally {
            frame.close()
            frameGate.release()
        }
    }

    private fun onMediaPipeError(@Suppress("UNUSED_PARAMETER") error: RuntimeException) {
        pending.getAndSet(null)?.close()
        frameGate.release()
        if (!closed.get()) onFailure("poseDetectionFailed")
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

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        cameraProvider?.unbindAll()
        cameraProvider = null
        cameraContainer.clearGuide()
        frameGate.reset()
        runCatching {
            analyzerExecutor.execute {
                landmarker?.close()
                landmarker = null
                pending.getAndSet(null)?.close()
                poseFilter.reset()
                extractor.reset()
                stats.reset()
            }
        }.onFailure {
            pending.getAndSet(null)?.close()
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
        const val PREVIEW_MIN_FPS = 24
        const val PREVIEW_TARGET_FPS = 30
    }
}
