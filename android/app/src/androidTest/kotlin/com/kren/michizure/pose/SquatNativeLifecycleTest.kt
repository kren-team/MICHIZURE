package com.kren.michizure.pose

import android.Manifest
import android.content.pm.PackageManager
import androidx.camera.view.PreviewView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SquatNativeLifecycleTest {
    @Test
    fun cameraPermissionIsDeclaredAndMlKitStreamDetectorInitializes() {
        val context =
            ApplicationProvider.getApplicationContext<android.content.Context>()
        val permission =
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_PERMISSIONS,
            ).requestedPermissions?.toSet().orEmpty()
        assertTrue(permission.contains(Manifest.permission.CAMERA))

        val detector =
            PoseDetection.getClient(
                PoseDetectorOptions.Builder()
                    .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
                    .build(),
            )
        assertNotNull(detector)
        detector.close()
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
        lateinit var preview: PreviewView
        instrumentation.runOnMainSync {
            owner.resume()
            manager =
                SquatSessionManager(owner) { _, _, _, _ ->
                    object : PoseSource {
                        override fun start() {
                            starts += 1
                        }

                        override fun close() {
                            closes += 1
                        }
                    }
                }
            preview = PreviewView(context)
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
        val detector =
            SquatStateMachine(
                SquatDetectorConfig(medianWindowSize = 1, emaAlpha = 1.0),
            )
        val updates =
            SyntheticLandmarkPoseSource().oneValidRep().map(detector::process)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
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
