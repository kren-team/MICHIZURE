package com.kren.michizure.pose

enum class PoseSourceMode {
    HOST_DEMO,
    ANDROID_LOCAL,
    ;

    val requiresCameraPermission: Boolean
        get() = this == ANDROID_LOCAL

    companion object {
        fun fromCreationParams(args: Any?): PoseSourceMode {
            val value = (args as? Map<*, *>)?.get("poseSource") as? String
            return if (value == "host") HOST_DEMO else ANDROID_LOCAL
        }
    }
}

class PoseSourceSelector<T>(
    private val hostFactory: () -> T,
    private val localFactory: () -> T,
) {
    fun create(mode: PoseSourceMode): T =
        when (mode) {
            PoseSourceMode.HOST_DEMO -> hostFactory()
            PoseSourceMode.ANDROID_LOCAL -> localFactory()
        }
}
