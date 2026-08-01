package com.kren.michizure.pose

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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
        val payload = packet(frameId = 7, jpeg = jpeg)
        val decoded = HostPoseProtocol.decodePacket(payload)

        assertEquals(7L, decoded.frameId)
        assertEquals(1234L, decoded.capturedAtMs)
        assertEquals(360, decoded.imageWidth)
        assertEquals(480, decoded.imageHeight)
        assertTrue(decoded.poseDetected)
        assertEquals(33, decoded.landmarks?.size)
        assertSame(payload, decoded.payload)
        assertArrayEquals(
            jpeg,
            decoded.payload.copyOfRange(
                decoded.jpegOffset,
                decoded.jpegOffset + decoded.jpegLength,
            ),
        )
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

        listOf(
            standingPacket(1, 0),
            standingPacket(1, 0),
            standingPacket(0, 250),
            standingPacket(2, 500),
        ).forEach {
            if (gate.accept(it.frameId)) {
                deliveries += 1
                machine.process(processor.process(it).feature)
            }
        }

        assertEquals(2, deliveries)
        assertEquals(SquatState.STANDING, machine.state)
    }

    @Test
    fun displaySlotKeepsOnlyLatestPacketAndNeverGrows() {
        val slot = LatestHostFrameSlot<Long>()

        assertEquals(LatestFrameOffer.ACCEPTED, slot.offer(1))
        repeat(100) { index ->
            assertEquals(LatestFrameOffer.REPLACED, slot.offer(index.toLong() + 2))
            assertEquals(1, slot.size)
        }

        assertEquals(101L, slot.takeLatest())
        assertEquals(0, slot.size)
    }

    @Test
    fun disposedDisplaySlotRejectsFurtherPackets() {
        val slot = LatestHostFrameSlot<Long>()
        slot.offer(1)

        assertEquals(1L, slot.dispose())
        assertEquals(LatestFrameOffer.REJECTED_DISPOSED, slot.offer(2))
        assertNull(slot.takeLatest())
    }

    @Test
    fun performanceWindowResetsCountersAndDoesNotProduceHugeFps() {
        val window = HostPerformanceWindow(startMs = 0, windowMs = 5_000)
        repeat(50) {
            window.recordReceived()
            window.recordStateMachine()
        }
        repeat(40) { window.recordDisplayed(drawDurationMs = 8) }
        window.recordDecoded(3)
        window.recordDroppedBeforeDecode()
        window.recordDroppedBeforeDraw()

        val first = requireNotNull(window.finishWindow(5_000))
        assertEquals(10.0, first.receiveFps, 0.01)
        assertEquals(10.0, first.stateMachineFps, 0.01)
        assertEquals(8.0, first.displayedFps, 0.01)
        assertEquals(3L, first.decodeP95Ms)
        assertEquals(8L, first.drawP95Ms)
        assertEquals(1L, first.droppedBeforeDecode)
        assertEquals(1L, first.droppedBeforeDraw)

        window.recordStateMachine()
        val second = requireNotNull(window.finishWindow(10_000))
        assertEquals(0.2, second.stateMachineFps, 0.01)
        assertNull(second.decodeP95Ms)
        assertEquals(0L, second.droppedBeforeDecode)
        assertEquals(0L, second.droppedBeforeDraw)
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
        return HostPosePacket(
            frameId = frameId,
            capturedAtMs = timestamp,
            inferenceMs = 10,
            imageWidth = 360,
            imageHeight = 480,
            poseDetected = true,
            landmarks = landmarks,
            payload = byteArrayOf(1),
            jpegOffset = 0,
            jpegLength = 1,
        )
    }

    private fun landmark(x: Double, y: Double) =
        MediaPipeLandmarkSample(x, y, 0.0, 0.99, 0.99)
}
