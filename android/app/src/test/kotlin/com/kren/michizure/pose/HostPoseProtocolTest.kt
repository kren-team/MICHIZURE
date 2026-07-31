package com.kren.michizure.pose

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostPoseProtocolTest {
    @Test
    fun hostModeSelectsHostFactoryWithoutInitializingLocalSource() {
        var localInitializations = 0
        val selected =
            PoseSourceSelector(
                hostFactory = { "host" },
                localFactory = { localInitializations += 1; "local" },
            ).create(PoseSourceMode.HOST_DEMO)

        assertEquals("host", selected)
        assertEquals(0, localInitializations)
        assertEquals(
            PoseSourceMode.HOST_DEMO,
            PoseSourceMode.fromCreationParams(mapOf("poseSource" to "host")),
        )
    }

    @Test
    fun binaryFrameContainsFrameIdTimestampRotationAndJpeg() {
        val encoded =
            HostPoseProtocol.encodeFrame(
                HostPoseFrameHeader(7, 1234, 320, 240, 90),
                byteArrayOf(1, 2, 3),
            )
        val buffer = ByteBuffer.wrap(encoded).order(ByteOrder.BIG_ENDIAN)

        assertEquals(0x4D504831, buffer.int)
        assertEquals(7L, buffer.long)
        assertEquals(1234L, buffer.long)
        assertEquals(320, buffer.int)
        assertEquals(240, buffer.int)
        assertEquals(90, buffer.int)
        assertEquals(3, buffer.int)
    }

    @Test
    fun staleAndDuplicateFrameIdsAreRejected() {
        val gate = HostPoseResultGate()

        assertTrue(gate.accept(10))
        assertFalse(gate.accept(10))
        assertFalse(gate.accept(9))
        assertTrue(gate.accept(11))
    }

    @Test
    fun normalizedHostLandmarksReachExistingStateMachine() {
        val processor = HostPoseResultProcessor()
        val machine = SquatStateMachine()

        val first = processor.process(standingResult(1, 0))
        val second = processor.process(standingResult(2, 500))

        assertTrue(first.feature is PoseFeatureResult.Valid)
        machine.process(first.feature)
        machine.process(second.feature)
        assertEquals(SquatState.STANDING, machine.state)
    }

    private fun standingResult(frameId: Long, timestamp: Long): HostPoseResult {
        val landmarks = MutableList(33) { landmark(0.5, 0.5) }
        landmarks[23] = landmark(0.40, 0.25)
        landmarks[25] = landmark(0.40, 0.50)
        landmarks[27] = landmark(0.40, 0.75)
        landmarks[24] = landmark(0.60, 0.25)
        landmarks[26] = landmark(0.60, 0.50)
        landmarks[28] = landmark(0.60, 0.75)
        return HostPoseResult(frameId, timestamp, 10, 320, 240, landmarks)
    }

    private fun landmark(x: Double, y: Double) =
        MediaPipeLandmarkSample(x, y, 0.0, 0.99, 0.99)
}
