package com.kren.michizure.pose

import android.Manifest
import android.content.pm.PackageManager
import android.view.View
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class SquatNativeLifecycleTest {
    @Test
    fun nativePreviewAndGuideShareExactlyTheSameThreeByFourBounds() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        instrumentation.runOnMainSync {
            val container = SquatCameraContainer(context)
            val width = View.MeasureSpec.makeMeasureSpec(300, View.MeasureSpec.EXACTLY)
            val height = View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY)
            container.measure(width, height)
            container.layout(0, 0, 300, 400)

            assertEquals(300, container.previewView.width)
            assertEquals(400, container.previewView.height)
            assertEquals(300, container.guideOverlayView.width)
            assertEquals(400, container.guideOverlayView.height)
            assertEquals(PreviewView.ScaleType.FIT_CENTER, container.previewView.scaleType)
            assertEquals(
                PreviewView.ImplementationMode.COMPATIBLE,
                container.previewView.implementationMode,
            )
        }
    }

    @Test
    fun cameraPermissionIsDeclaredAndMediaPipeLiteModelInitializes() {
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val permission =
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_PERMISSIONS,
            ).requestedPermissions?.toSet().orEmpty()
        assertTrue(permission.contains(Manifest.permission.CAMERA))

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
                .setResultListener { _, _ -> }
                .setErrorListener { }
                .build()
        val landmarker = PoseLandmarker.createFromOptions(context, options)
        assertNotNull(landmarker)
        landmarker.close()
    }

    @Test
    fun generatedDebugFixtureProducesCallbackPoseAndLowerBodyLandmarks() {
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val completed = CountDownLatch(1)
        val result = AtomicReference<PoseFixtureDiagnosticResult?>()
        val diagnostics = GeneratedPoseFixtureDiagnostics(context)
        try {
            diagnostics.run {
                result.set(it)
                completed.countDown()
            }

            assertTrue(completed.await(8, TimeUnit.SECONDS))
            val actual = requireNotNull(result.get())
            assertTrue(actual.callbackDelivered)
            assertTrue(actual.poseCount >= 1)
            assertTrue(actual.hipAvailable)
            assertTrue(actual.kneeAvailable)
            assertTrue(actual.ankleAvailable)
            assertEquals(null, actual.errorCode)
        } finally {
            diagnostics.close()
        }
    }

    @Test
    fun previewLifecycleStartsOnceAndReleasesOnDispose() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val owner = TestLifecycleOwner()
        var starts = 0
        var closes = 0
        lateinit var manager: SquatSessionManager
        lateinit var preview: SquatCameraContainer
        instrumentation.runOnMainSync {
            owner.resume()
            manager =
                SquatSessionManager(owner) { _, _, onReady, _, _, _ ->
                    object : PoseSource {
                        override fun start() {
                            starts += 1
                            onReady(PoseDelegate.CPU)
                        }

                        override fun close() {
                            closes += 1
                        }
                    }
                }
            preview = SquatCameraContainer(context)
            manager.attachPreview(preview)
            assertTrue(
                manager.start(
                    NativeSquatSession(
                        squatSessionId = "session-12345678",
                        debtId = "debt-1",
                    ),
                ),
            )
            assertTrue(
                !manager.start(
                    NativeSquatSession(
                        squatSessionId = "session-12345678",
                        debtId = "debt-1",
                    ),
                ),
            )
            manager.detachPreview(preview)
            manager.close()
            owner.destroy()
        }

        assertEquals(1, starts)
        assertEquals(1, closes)
    }

    @Test
    fun debugSyntheticSequenceUsesProductionStateMachineExactlyOnce() {
        val detector = SquatStateMachine()
        val updates =
            SyntheticLandmarkPoseSource().oneValidRep().map(detector::process)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun cameraProviderFailureIsDeliveredAsTypedEvent() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val owner = TestLifecycleOwner()
        val failureDelivered = CountDownLatch(1)
        val events = mutableListOf<Map<String, Any?>>()
        lateinit var manager: SquatSessionManager

        SquatEventBus.setListener { event ->
            events += event
            if (event["type"] == "detectorError") failureDelivered.countDown()
        }
        try {
            instrumentation.runOnMainSync {
                owner.resume()
                manager =
                    SquatSessionManager(owner) { _, _, _, _, _, onFailure ->
                        object : PoseSource {
                            override fun start() {
                                onFailure("cameraUnavailable")
                            }

                            override fun close() = Unit
                        }
                    }
                val preview = SquatCameraContainer(context)
                manager.attachPreview(preview)
                manager.start(
                    NativeSquatSession(
                        squatSessionId = "session-12345678",
                        debtId = "debt-1",
                    ),
                )
            }

            assertTrue(failureDelivered.await(2, TimeUnit.SECONDS))
            val failure = events.single { it["type"] == "detectorError" }
            assertEquals("cameraUnavailable", failure["code"])
            assertEquals("session-12345678", failure["squatSessionId"])
        } finally {
            instrumentation.runOnMainSync {
                manager.close()
                owner.destroy()
            }
            SquatEventBus.setListener(null)
        }
    }

    @Test
    fun debugSessionDeliversDerivedLowerBodyDiagnosticsWithoutCoordinates() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val owner = TestLifecycleOwner()
        val diagnosticsDelivered = CountDownLatch(1)
        val events = mutableListOf<Map<String, Any?>>()
        lateinit var manager: SquatSessionManager

        SquatEventBus.setListener { event ->
            events += event
            if (event["type"] == "diagnostics" && event["selectedSide"] == "left") {
                diagnosticsDelivered.countDown()
            }
        }
        try {
            instrumentation.runOnMainSync {
                owner.resume()
                manager =
                    SquatSessionManager(owner) { _, _, onReady, onStatus, onFrame, _ ->
                        object : PoseSource {
                            override fun start() {
                                onReady(PoseDelegate.CPU)
                                onStatus(
                                    PosePipelineStatusSnapshot(
                                        status = PosePipelineStatus.VALID,
                                        metrics =
                                            PosePipelineMetrics(
                                                activeDelegate = PoseDelegate.CPU,
                                            ),
                                    ),
                                )
                                onFrame(
                                    PoseFrameDelivery(
                                        feature =
                                            PoseFeatureResult.Valid(
                                                PoseFeatureSample(
                                                    timestampMs = 1_000,
                                                    kneeAngleDeg = 170.0,
                                                    hipY = 0.25,
                                                    legLength = 0.50,
                                                    confidence = 0.90,
                                                    selectedSide = PoseSide.LEFT,
                                                ),
                                                PoseQualityMetrics.EMPTY.copy(
                                                    poseDetected = true,
                                                    leftHipConfidence = 0.90,
                                                    leftKneeConfidence = 0.91,
                                                    leftAnkleConfidence = 0.92,
                                                    selectedSide = PoseSide.LEFT,
                                                ),
                                            ),
                                        latency =
                                            PoseLatencySample(
                                                analyzerReceivedNs = 1,
                                                preprocessingStartedNs = 2,
                                                inferenceSubmittedNs = 3,
                                                inferenceCallbackNs = 4,
                                                stateMachineCompletedNs = 4,
                                                nativeEventDispatchedNs = null,
                                            ),
                                        metrics = PosePipelineMetrics(),
                                        delegate = PoseDelegate.CPU,
                                    ),
                                )
                            }

                            override fun close() = Unit
                        }
                    }
                val preview = SquatCameraContainer(context)
                manager.attachPreview(preview)
                manager.start(
                    NativeSquatSession(
                        squatSessionId = "session-12345678",
                        debtId = "debt-1",
                    ),
                )
            }

            assertTrue(diagnosticsDelivered.await(2, TimeUnit.SECONDS))
            val diagnostics =
                events.first {
                    it["type"] == "diagnostics" && it["selectedSide"] == "left"
                }
            assertEquals(true, diagnostics["poseDetected"])
            assertEquals("left", diagnostics["selectedSide"])
            assertFalse(diagnostics.containsKey("landmarks"))
            assertFalse(diagnostics.containsKey("frame"))
            assertFalse(diagnostics.containsKey("image"))
        } finally {
            instrumentation.runOnMainSync {
                manager.close()
                owner.destroy()
            }
            SquatEventBus.setListener(null)
        }
    }
}

private class TestLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    override val lifecycle: Lifecycle
        get() = registry

    fun resume() {
        registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_START)
        registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
    }

    fun destroy() {
        registry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
    }
}
