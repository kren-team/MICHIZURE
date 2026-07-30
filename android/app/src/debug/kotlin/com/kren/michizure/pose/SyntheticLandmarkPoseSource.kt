package com.kren.michizure.pose

/**
 * Debug/test-only numeric source. It never contains camera pixels and is not
 * referenced by the release graph.
 */
class SyntheticLandmarkPoseSource {
    fun oneValidRep(startTimestampMs: Long = 0): List<PoseFeatureResult> {
        val frames = mutableListOf<PoseFeatureResult>()
        repeat(11) { index ->
            frames += sample(startTimestampMs + index * 100, 170.0, 0.25)
        }
        val movementStart = startTimestampMs + 1_100
        frames += sample(movementStart, 145.0, 0.30)
        frames += sample(movementStart + 100, 125.0, 0.34)
        frames += sample(movementStart + 200, 100.0, 0.40)
        frames += sample(movementStart + 300, 100.0, 0.40)
        frames += sample(movementStart + 500, 120.0, 0.36)
        frames += sample(movementStart + 700, 150.0, 0.30)
        frames += sample(movementStart + 900, 165.0, 0.25)
        frames += sample(movementStart + 1_150, 170.0, 0.25)
        return frames
    }

    private fun sample(
        timestampMs: Long,
        knee: Double,
        hipY: Double,
    ) = PoseFeatureResult.Valid(
        PoseFeatureSample(
            timestampMs = timestampMs,
            kneeAngleDeg = knee,
            hipY = hipY,
            legLength = 0.50,
            confidence = 0.90,
            selectedSide = PoseSide.LEFT,
        ),
    )
}
