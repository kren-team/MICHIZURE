package com.kren.michizure.pose

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

data class HostPosePacket(
    val frameId: Long,
    val capturedAtMs: Long,
    val inferenceMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val poseDetected: Boolean,
    val landmarks: List<MediaPipeLandmarkSample>?,
    val jpeg: ByteArray,
)

object HostPoseProtocol {
    const val PROTOCOL_VERSION = 1

    fun decodePacket(message: ByteArray): HostPosePacket {
        require(message.size >= HEADER_LENGTH_BYTES) { "packet is too short" }
        require(message.size <= MAX_PACKET_BYTES) { "packet is too large" }
        val headerLength =
            ByteBuffer.wrap(message, 0, HEADER_LENGTH_BYTES)
                .order(ByteOrder.BIG_ENDIAN)
                .int
        require(headerLength in 1..MAX_HEADER_BYTES) { "invalid header length" }
        val jpegOffset = HEADER_LENGTH_BYTES + headerLength
        require(jpegOffset <= message.size) { "truncated header" }
        val json = JSONObject(message.copyOfRange(HEADER_LENGTH_BYTES, jpegOffset).toString(Charsets.UTF_8))
        require(json.getInt("protocolVersion") == PROTOCOL_VERSION) { "unsupported protocol" }
        val frameId = json.getLong("frameId")
        val capturedAtMs = json.getLong("capturedAtMs")
        val imageWidth = json.getInt("imageWidth")
        val imageHeight = json.getInt("imageHeight")
        val inferenceMs = json.getLong("inferenceMs")
        val jpegLength = json.getInt("jpegLength")
        val poseDetected = json.getBoolean("poseDetected")
        require(frameId > 0 && capturedAtMs >= 0) { "invalid frame metadata" }
        require(imageWidth > 0 && imageHeight > 0) { "invalid image dimensions" }
        require(inferenceMs >= 0 && jpegLength > 0) { "invalid payload metadata" }
        require(jpegOffset + jpegLength == message.size) { "JPEG length mismatch" }

        val values = json.getJSONArray("landmarks")
        val landmarks =
            List(values.length()) { index ->
                val item = values.getJSONObject(index)
                MediaPipeLandmarkSample(
                    x = item.getFiniteDouble("x"),
                    y = item.getFiniteDouble("y"),
                    z = item.getFiniteDouble("z"),
                    visibility = item.getOptionalFiniteDouble("visibility"),
                    presence = item.getOptionalFiniteDouble("presence"),
                )
            }.takeIf { it.isNotEmpty() }
        require(poseDetected == (landmarks != null)) { "pose flag does not match landmarks" }
        return HostPosePacket(
            frameId = frameId,
            capturedAtMs = capturedAtMs,
            inferenceMs = inferenceMs,
            imageWidth = imageWidth,
            imageHeight = imageHeight,
            poseDetected = poseDetected,
            landmarks = landmarks,
            jpeg = message.copyOfRange(jpegOffset, message.size),
        )
    }

    private fun JSONObject.getFiniteDouble(name: String): Double =
        getDouble(name).also { require(it.isFinite()) { "$name is not finite" } }

    private fun JSONObject.getOptionalFiniteDouble(name: String): Double? =
        if (!has(name) || isNull(name)) null else getFiniteDouble(name)

    private const val HEADER_LENGTH_BYTES = 4
    private const val MAX_HEADER_BYTES = 128 * 1024
    private const val MAX_PACKET_BYTES = 4 * 1024 * 1024
}

class HostPoseResultGate {
    private var lastAcceptedFrameId = Long.MIN_VALUE

    @Synchronized
    fun accept(frameId: Long): Boolean {
        if (frameId <= lastAcceptedFrameId) return false
        lastAcceptedFrameId = frameId
        return true
    }

    @Synchronized
    fun reset() {
        lastAcceptedFrameId = Long.MIN_VALUE
    }
}

data class ProcessedHostPose(
    val pose: LowerBodyPose,
    val filteredPose: LowerBodyPose,
    val feature: PoseFeatureResult,
)

class HostPoseResultProcessor(
    config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    private val filter = LowerBodyPoseFilter(config)
    private val extractor = PoseFeatureExtractor(config)

    fun process(result: HostPosePacket): ProcessedHostPose {
        val pose =
            MediaPipePoseAdapter.convert(
                MediaPipePoseResultSample(
                    timestampMs = result.capturedAtMs,
                    imageWidth = result.imageWidth,
                    imageHeight = result.imageHeight,
                    landmarks = result.landmarks,
                ),
            )
        val filteredPose = filter.filter(pose)
        val filteredFeature = extractor.extract(filteredPose)
        val feature =
            when (filteredFeature) {
                is PoseFeatureResult.Valid ->
                    filteredFeature.copy(sample = filteredFeature.sample.withRawAngle(pose))
                is PoseFeatureResult.CalibrationCandidate ->
                    filteredFeature.copy(sample = filteredFeature.sample.withRawAngle(pose))
                is PoseFeatureResult.Invalid -> filteredFeature
            }
        return ProcessedHostPose(pose, filteredPose, feature)
    }

    fun reset() {
        filter.reset()
        extractor.reset()
    }

    private fun PoseFeatureSample.withRawAngle(pose: LowerBodyPose): PoseFeatureSample =
        copy(rawKneeAngleDeg = extractor.kneeAngleForSide(pose, selectedSide) ?: kneeAngleDeg)
}
