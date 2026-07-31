package com.kren.michizure.pose

/**
 * Debug/test-only numeric source. It never contains camera pixels and is not
 * referenced by the release graph.
 */
class SyntheticLandmarkPoseSource {
    fun oneValidRep(startTimestampMs: Long = 0): List<PoseFeatureResult> {
        val frames = mutableListOf<PoseFeatureResult>()
        CALIBRATION_OFFSETS_MS.forEach { offsetMs ->
            frames += sample(startTimestampMs + offsetMs, 170.0, 0.25)
        }
        val movementStart = startTimestampMs + 2_300
        frames += sample(movementStart, 145.0, 0.29)
        frames += sample(movementStart + 100, 140.0, 0.30)
        frames += sample(movementStart + 200, 120.0, 0.32)
        frames += sample(movementStart + 300, 100.0, 0.36)
        frames += sample(movementStart + 450, 100.0, 0.36)
        frames += sample(movementStart + 550, 125.0, 0.33)
        frames += sample(movementStart + 650, 135.0, 0.32)
        frames += sample(movementStart + 850, 160.0, 0.27)
        frames += sample(movementStart + 1_100, 170.0, 0.25)
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

    private companion object {
        val CALIBRATION_OFFSETS_MS =
            listOf(0L, 300L, 600L, 900L, 1_200L, 1_500L, 1_800L, 2_100L)
    }
}
