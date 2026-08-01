package com.kren.michizure.platform

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceControlContractTest {
    @Test
    fun acceptsOnlyTheCurrentContractVersion() {
        assertTrue(
            DeviceControlContract.hasSupportedVersion(
                mapOf("contractVersion" to 1),
            ),
        )
        assertFalse(
            DeviceControlContract.hasSupportedVersion(
                mapOf("contractVersion" to 2),
            ),
        )
        assertFalse(DeviceControlContract.hasSupportedVersion(null))
    }
}
