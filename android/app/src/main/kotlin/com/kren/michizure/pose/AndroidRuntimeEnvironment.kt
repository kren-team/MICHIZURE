package com.kren.michizure.pose

import android.os.Build

data class AndroidRuntimeEnvironment(
    val fingerprint: String,
    val model: String,
    val manufacturer: String,
    val brand: String,
    val device: String,
    val product: String,
    val hardware: String,
) {
    val isEmulator: Boolean
        get() =
            fingerprint.startsWith("generic") ||
                fingerprint.contains("emulator", ignoreCase = true) ||
                model.contains("Emulator", ignoreCase = true) ||
                model.contains("Android SDK built for", ignoreCase = true) ||
                manufacturer.contains("Genymotion", ignoreCase = true) ||
                (brand.startsWith("generic") && device.startsWith("generic")) ||
                product.contains("sdk", ignoreCase = true) ||
                hardware.contains("goldfish", ignoreCase = true) ||
                hardware.contains("ranchu", ignoreCase = true)

    fun shouldPreferGpu(configPreference: Boolean): Boolean =
        configPreference && !isEmulator

    companion object {
        fun current(): AndroidRuntimeEnvironment =
            AndroidRuntimeEnvironment(
                fingerprint = Build.FINGERPRINT.orEmpty(),
                model = Build.MODEL.orEmpty(),
                manufacturer = Build.MANUFACTURER.orEmpty(),
                brand = Build.BRAND.orEmpty(),
                device = Build.DEVICE.orEmpty(),
                product = Build.PRODUCT.orEmpty(),
                hardware = Build.HARDWARE.orEmpty(),
            )
    }
}
