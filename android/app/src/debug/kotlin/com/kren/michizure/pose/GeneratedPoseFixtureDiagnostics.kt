package com.kren.michizure.pose

import android.content.Context
import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class GeneratedPoseFixtureDiagnostics(
    private val context: Context,
) : DebugPoseFixtureDiagnostics {
    private val executor = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)

    override fun run(callback: (PoseFixtureDiagnosticResult) -> Unit) {
        if (closed.get() || !running.compareAndSet(false, true)) {
            callback(failure("fixture_diagnostic_busy"))
            return
        }
        executor.execute {
            val result = runFixture()
            running.set(false)
            callback(result)
        }
    }

    private fun runFixture(): PoseFixtureDiagnosticResult {
        val callbackLatch = CountDownLatch(1)
        val callbackResult = AtomicReference<PoseFixtureDiagnosticResult?>()
        val landmarker =
            runCatching {
                val options =
                    PoseLandmarker.PoseLandmarkerOptions.builder()
                        .setBaseOptions(
                            BaseOptions.builder()
                                .setModelAssetPath(SquatDetectorConfig.MODEL_ASSET)
                                .setDelegate(Delegate.CPU)
                                .build(),
                        )
                        .setRunningMode(RunningMode.LIVE_STREAM)
                        .setNumPoses(1)
                        .setOutputSegmentationMasks(false)
                        .setResultListener { result, input ->
                            try {
                                val landmarks = result.landmarks().firstOrNull()
                                callbackResult.compareAndSet(
                                    null,
                                    PoseFixtureDiagnosticResult(
                                        callbackDelivered = true,
                                        poseCount = result.landmarks().size,
                                        hipAvailable = hasEither(landmarks, LEFT_HIP, RIGHT_HIP),
                                        kneeAvailable = hasEither(landmarks, LEFT_KNEE, RIGHT_KNEE),
                                        ankleAvailable =
                                            hasEither(landmarks, LEFT_ANKLE, RIGHT_ANKLE),
                                        errorCode = null,
                                    ),
                                )
                            } finally {
                                input.close()
                                callbackLatch.countDown()
                            }
                        }
                        .setErrorListener {
                            callbackResult.compareAndSet(
                                null,
                                failure("fixture_inference_error"),
                            )
                            callbackLatch.countDown()
                        }
                        .build()
                PoseLandmarker.createFromOptions(context, options)
            }.getOrElse {
                return failure("fixture_initialization_error")
            }
        try {
            val bitmap =
                context.assets.open(FIXTURE_ASSET).use(BitmapFactory::decodeStream)
                    ?: return failure("fixture_decode_error")
            val image = BitmapImageBuilder(bitmap).build()
            try {
                landmarker.detectAsync(image, FIXTURE_TIMESTAMP_MS)
            } catch (_: RuntimeException) {
                return failure("fixture_submission_error")
            } finally {
                image.close()
                bitmap.recycle()
            }
            if (!callbackLatch.await(CALLBACK_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                return failure("fixture_callback_timeout")
            }
            return callbackResult.get() ?: failure("fixture_callback_missing")
        } finally {
            landmarker.close()
        }
    }

    private fun hasEither(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>?,
        leftIndex: Int,
        rightIndex: Int,
    ): Boolean =
        listOf(leftIndex, rightIndex).any { index ->
            val landmark = landmarks?.getOrNull(index) ?: return@any false
            val visibility = landmark.visibility().orElse(0f)
            val presence = landmark.presence().orElse(0f)
            landmark.x().isFinite() &&
                landmark.y().isFinite() &&
                visibility >= MIN_FIXTURE_CONFIDENCE &&
                presence >= MIN_FIXTURE_CONFIDENCE
        }

    private fun failure(code: String) =
        PoseFixtureDiagnosticResult(
            callbackDelivered = false,
            poseCount = 0,
            hipAvailable = false,
            kneeAvailable = false,
            ankleAvailable = false,
            errorCode = code,
        )

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        executor.shutdownNow()
    }

    private companion object {
        const val FIXTURE_ASSET = "pose_fixture_generated.png"
        const val FIXTURE_TIMESTAMP_MS = 1L
        const val CALLBACK_TIMEOUT_SECONDS = 5L
        const val MIN_FIXTURE_CONFIDENCE = 0.50f
        const val LEFT_HIP = 23
        const val RIGHT_HIP = 24
        const val LEFT_KNEE = 25
        const val RIGHT_KNEE = 26
        const val LEFT_ANKLE = 27
        const val RIGHT_ANKLE = 28
    }
}
