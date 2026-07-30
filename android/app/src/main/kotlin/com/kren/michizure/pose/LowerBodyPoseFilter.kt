package com.kren.michizure.pose

/**
 * Independent filters per anatomical side prevent a left/right switch from
 * carrying the previous leg's coordinate history into the new side.
 */
class LowerBodyPoseFilter(
    config: SquatDetectorConfig = SquatDetectorConfig(),
) {
    private val left = SideFilter(config)
    private val right = SideFilter(config)
    private var lastTimestampMs: Long? = null

    fun filter(pose: LowerBodyPose): LowerBodyPose {
        val previous = lastTimestampMs
        if (previous != null && pose.timestampMs <= previous) return pose
        if (!pose.poseDetected) {
            reset()
            return pose
        }
        lastTimestampMs = pose.timestampMs
        return pose.copy(
            left = pose.left?.let { left.filter(it, pose.timestampMs) },
            right = pose.right?.let { right.filter(it, pose.timestampMs) },
        )
    }

    fun reset() {
        lastTimestampMs = null
        left.reset()
        right.reset()
    }

    private class SideFilter(config: SquatDetectorConfig) {
        private val hip = PointFilter(config)
        private val knee = PointFilter(config)
        private val ankle = PointFilter(config)

        fun filter(
            side: LowerBodySide,
            timestampMs: Long,
        ) = LowerBodySide(
            hip = side.hip?.let { hip.filter(it, timestampMs) },
            knee = side.knee?.let { knee.filter(it, timestampMs) },
            ankle = side.ankle?.let { ankle.filter(it, timestampMs) },
        )

        fun reset() {
            hip.reset()
            knee.reset()
            ankle.reset()
        }
    }

    private class PointFilter(config: SquatDetectorConfig) {
        private val x =
            OneEuroFilter(
                minCutoff = config.oneEuroMinCutoff,
                beta = config.oneEuroBeta,
                derivativeCutoff = config.oneEuroDerivativeCutoff,
                longGapMs = config.oneEuroLongGapMs,
            )
        private val y =
            OneEuroFilter(
                minCutoff = config.oneEuroMinCutoff,
                beta = config.oneEuroBeta,
                derivativeCutoff = config.oneEuroDerivativeCutoff,
                longGapMs = config.oneEuroLongGapMs,
            )

        fun filter(
            point: PosePoint,
            timestampMs: Long,
        ): PosePoint {
            val filteredX = x.filter(point.x, timestampMs) ?: point.x
            val filteredY = y.filter(point.y, timestampMs) ?: point.y
            return point.copy(x = filteredX, y = filteredY)
        }

        fun reset() {
            x.reset()
            y.reset()
        }
    }
}
