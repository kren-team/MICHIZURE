package com.kren.michizure.pose

import android.content.Context
import android.os.SystemClock
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class CameraMlKitPoseSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val previewView: PreviewView,
    private val onFrame: (PoseFeatureResult, Long) -> Unit,
    private val onFailure: (String) -> Unit,
) : PoseSource {
    private val analyzerExecutor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "michizure-pose-analyzer")
        }
    private val frameLeaseGate = FrameLeaseGate()
    private val detector =
        PoseDetection.getClient(
            PoseDetectorOptions.Builder()
                .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
                .build(),
        )
    private val extractor = PoseFeatureExtractor()
    private var cameraProvider: ProcessCameraProvider? = null
    @Volatile private var closed = false

    override fun start() {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener(
            {
                if (closed) return@addListener
                runCatching {
                    val provider = future.get()
                    cameraProvider = provider
                    bind(provider)
                }.onFailure { onFailure("cameraUnavailable") }
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    private fun bind(provider: ProcessCameraProvider) {
        val front =
            CameraSelector.DEFAULT_FRONT_CAMERA.takeIf {
                provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
            }
        val selector =
            front
                ?: CameraSelector.DEFAULT_BACK_CAMERA.takeIf {
                    provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
                }
                ?: error("No camera is available")
        val isFront = selector == CameraSelector.DEFAULT_FRONT_CAMERA
        val preview =
            Preview.Builder().build().also {
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
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()
                .also { useCase ->
                    useCase.setAnalyzer(analyzerExecutor) { image ->
                        analyze(image, isFront)
                    }
                }
        provider.unbindAll()
        provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
    }

    private fun analyze(
        imageProxy: ImageProxy,
        isFront: Boolean,
    ) {
        if (closed) {
            imageProxy.close()
            return
        }
        val lease = frameLeaseGate.tryAcquire(imageProxy::close)
        if (lease == null) {
            imageProxy.close()
            return
        }
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            lease.close()
            return
        }
        val frameElapsedMs = imageProxy.imageInfo.timestamp / 1_000_000
        val rotation = imageProxy.imageInfo.rotationDegrees
        val (outputWidth, outputHeight) =
            PoseCoordinateNormalizer.outputSize(
                imageProxy.width,
                imageProxy.height,
                rotation,
            )
        val input = InputImage.fromMediaImage(mediaImage, rotation)
        detector.process(input)
            .addOnSuccessListener { pose ->
                val frame =
                    MlKitPoseAdapter.convert(
                        pose = pose,
                        timestampMs = frameElapsedMs,
                        imageWidth = outputWidth,
                        imageHeight = outputHeight,
                        mirrorHorizontally = isFront,
                    )
                val latencyMs =
                    (SystemClock.elapsedRealtimeNanos() / 1_000_000 - frameElapsedMs)
                        .coerceAtLeast(0)
                onFrame(extractor.extract(frame), latencyMs)
            }
            .addOnFailureListener { onFailure("poseDetectionFailed") }
            .addOnCompleteListener {
                lease.close()
            }
    }

    override fun close() {
        if (closed) return
        closed = true
        cameraProvider?.unbindAll()
        cameraProvider = null
        detector.close()
        analyzerExecutor.shutdown()
        extractor.reset()
    }
}

interface PoseSource : AutoCloseable {
    fun start()
}
