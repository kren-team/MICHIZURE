package com.kren.michizure.pose

/**
 * Debug/test-only numeric source. It never contains camera pixels and is not
 * referenced by the release graph.
 */
class SyntheticLandmarkPoseSource {
    fun oneValidRep(startTimestampMs: Long = 0): List<PoseFeatureResult> {
        val frames = mutableListOf<PoseFeatureResult>()
        repeat(11) { index ->
            frames += sample(startTimestampMs + index * 100, hipY = 0.25, kneeY = 0.50)
        }
        val movementStart = startTimestampMs + 1_100
        frames += sample(movementStart, hipY = 0.29, kneeY = 0.45)
        frames += sample(movementStart + 100, hipY = 0.30, kneeY = 0.46)
        frames += sample(movementStart + 200, hipY = 0.35, kneeY = 0.42)
        frames += sample(movementStart + 300, hipY = 0.35, kneeY = 0.42)
        frames += sample(movementStart + 400, hipY = 0.35, kneeY = 0.42)
        frames += sample(movementStart + 500, hipY = 0.31, kneeY = 0.44)
        frames += sample(movementStart + 600, hipY = 0.31, kneeY = 0.44)
        frames += sample(movementStart + 700, hipY = 0.25, kneeY = 0.50)
        frames += sample(movementStart + 900, hipY = 0.25, kneeY = 0.50)
        frames += sample(movementStart + 1_000, hipY = 0.25, kneeY = 0.50)
        return frames
    }

    private fun sample(
        timestampMs: Long,
        hipY: Double,
        kneeY: Double,
    ) = PoseFeatureResult.Valid(
        PoseFeatureSample(
            timestampMs = timestampMs,
            hipY = hipY,
            kneeY = kneeY,
            confidence = 0.90,
            selectedSide = PoseSide.LEFT,
        ),
    )
}
