package com.kren.michizure.pose

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class HostPoseProtocolTest {
    @Test
    fun hostModeSelectsReceiveOnlyFactoryWithoutInitializingLocalSource() {
        var localInitializations = 0
        val selected =
            PoseSourceSelector(
                hostFactory = { "host-receive-only" },
                localFactory = { localInitializations += 1; "local-camera" },
            ).create(PoseSourceMode.HOST_DEMO)

        assertEquals("host-receive-only", selected)
        assertEquals(0, localInitializations)
        assertFalse(PoseSourceMode.HOST_DEMO.requiresCameraPermission)
        assertTrue(PoseSourceMode.ANDROID_LOCAL.requiresCameraPermission)
    }

    @Test
    fun packetParsesHeaderLandmarksAndJpeg() {
        val jpeg = byteArrayOf(1, 2, 3)
        val decoded = HostPoseProtocol.decodePacket(packet(frameId = 7, jpeg = jpeg))

        assertEquals(7L, decoded.frameId)
        assertEquals(1234L, decoded.capturedAtMs)
        assertEquals(360, decoded.imageWidth)
        assertEquals(480, decoded.imageHeight)
        assertTrue(decoded.poseDetected)
        assertEquals(33, decoded.landmarks?.size)
        assertArrayEquals(jpeg, decoded.jpeg)
    }

    @Test
    fun invalidVersionLengthAndMalformedHeaderAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            HostPoseProtocol.decodePacket(packet(protocolVersion = 2))
        }
        assertThrows(IllegalArgumentException::class.java) {
            HostPoseProtocol.decodePacket(packet(jpegLengthOverride = 99))
        }
        assertThrows(Exception::class.java) {
            HostPoseProtocol.decodePacket(byteArrayOf(0, 0, 0, 2, '{'.code.toByte()))
        }
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
    fun eachAcceptedNormalizedFrameReachesExistingStateMachineOnce() {
        val gate = HostPoseResultGate()
        val processor = HostPoseResultProcessor()
        val machine = SquatStateMachine()
        var deliveries = 0

        listOf(standingPacket(1, 0), standingPacket(1, 0), standingPacket(2, 500)).forEach {
            if (gate.accept(it.frameId)) {
                deliveries += 1
                machine.process(processor.process(it).feature)
            }
        }

        assertEquals(2, deliveries)
        assertEquals(SquatState.STANDING, machine.state)
    }

    private fun packet(
        frameId: Long = 7,
        protocolVersion: Int = HostPoseProtocol.PROTOCOL_VERSION,
        jpeg: ByteArray = byteArrayOf(1),
        jpegLengthOverride: Int? = null,
    ): ByteArray {
        val landmarks =
            JSONArray().apply {
                repeat(33) {
                    put(
                        JSONObject()
                            .put("x", 0.5)
                            .put("y", 0.5)
                            .put("z", 0.0)
                            .put("visibility", 0.99)
                            .put("presence", 0.99),
                    )
                }
            }
        val header =
            JSONObject()
                .put("protocolVersion", protocolVersion)
                .put("frameId", frameId)
                .put("capturedAtMs", 1234)
                .put("imageWidth", 360)
                .put("imageHeight", 480)
                .put("jpegLength", jpegLengthOverride ?: jpeg.size)
                .put("inferenceMs", 10)
                .put("poseDetected", true)
                .put("landmarks", landmarks)
                .toString()
                .toByteArray()
        return ByteBuffer.allocate(4 + header.size + jpeg.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(header.size)
            .put(header)
            .put(jpeg)
            .array()
    }

    private fun standingPacket(frameId: Long, timestamp: Long): HostPosePacket {
        val landmarks = MutableList(33) { landmark(0.5, 0.5) }
        landmarks[23] = landmark(0.40, 0.25)
        landmarks[25] = landmark(0.40, 0.50)
        landmarks[27] = landmark(0.40, 0.75)
        landmarks[24] = landmark(0.60, 0.25)
        landmarks[26] = landmark(0.60, 0.50)
        landmarks[28] = landmark(0.60, 0.75)
        return HostPosePacket(frameId, timestamp, 10, 360, 480, true, landmarks, byteArrayOf(1))
    }

    private fun landmark(x: Double, y: Double) =
        MediaPipeLandmarkSample(x, y, 0.0, 0.99, 0.99)
}
