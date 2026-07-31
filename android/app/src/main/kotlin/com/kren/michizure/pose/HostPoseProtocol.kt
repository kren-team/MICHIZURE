package com.kren.michizure.pose

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

data class HostPoseFrameHeader(
    val frameId: Long,
    val timestampMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val rotationDegrees: Int,
)

data class HostPoseResult(
    val frameId: Long,
    val timestampMs: Long,
    val inferenceMs: Long,
    val imageWidth: Int,
    val imageHeight: Int,
    val landmarks: List<MediaPipeLandmarkSample>?,
)

object HostPoseProtocol {
    const val HEADER_SIZE = 36

    fun encodeFrame(header: HostPoseFrameHeader, jpeg: ByteArray): ByteArray =
        ByteBuffer.allocate(HEADER_SIZE + jpeg.size)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(MAGIC)
            .putLong(header.frameId)
            .putLong(header.timestampMs)
            .putInt(header.imageWidth)
            .putInt(header.imageHeight)
            .putInt(header.rotationDegrees)
            .putInt(jpeg.size)
            .put(jpeg)
            .array()

    fun decodeResult(text: String): HostPoseResult {
        val json = JSONObject(text)
        val values = json.optJSONArray("landmarks")
        val landmarks =
            values?.let { array ->
                List(array.length()) { index ->
                    val item = array.getJSONObject(index)
                    MediaPipeLandmarkSample(
                        x = item.getDouble("x"),
                        y = item.getDouble("y"),
                        z = item.getDouble("z"),
                        visibility = item.optDoubleOrNull("visibility"),
                        presence = item.optDoubleOrNull("presence"),
                    )
                }
            }?.takeIf { it.isNotEmpty() }
        return HostPoseResult(
            frameId = json.getLong("frameId"),
            timestampMs = json.getLong("timestamp"),
            inferenceMs = json.getLong("inferenceMs"),
            imageWidth = json.getInt("imageWidth"),
            imageHeight = json.getInt("imageHeight"),
            landmarks = landmarks,
        )
    }

    private fun JSONObject.optDoubleOrNull(name: String): Double? =
        if (isNull(name) || !has(name)) null else getDouble(name)

    private const val MAGIC = 0x4D504831 // MPH1
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

    fun process(result: HostPoseResult): ProcessedHostPose {
        val pose =
            MediaPipePoseAdapter.convert(
                MediaPipePoseResultSample(
                    timestampMs = result.timestampMs,
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
                    filteredFeature.copy(
                        sample = filteredFeature.sample.withRawAngle(pose),
                    )
                is PoseFeatureResult.CalibrationCandidate ->
                    filteredFeature.copy(
                        sample = filteredFeature.sample.withRawAngle(pose),
                    )
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
