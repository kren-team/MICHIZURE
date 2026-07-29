package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatContractTest {
    @Test
    fun acceptsOnlyContractVersionOne() {
        assertTrue(SquatContract.supports(mapOf("contractVersion" to 1)))
        assertFalse(SquatContract.supports(mapOf("contractVersion" to 2)))
        assertFalse(SquatContract.supports(null))
    }

    @Test
    fun channelNamesAreVersionedAndPayloadIsMinimal() {
        assertTrue(SquatContract.METHOD_CHANNEL.endsWith("/v1"))
        assertTrue(SquatContract.EVENT_CHANNEL.endsWith("/v1"))
        assertTrue(SquatContract.PREVIEW_VIEW_TYPE.endsWith("/v1"))
        assertEquals(
            mapOf("contractVersion" to 1, "state" to "standing"),
            SquatContract.versioned(mapOf("state" to "standing")),
        )
    }
}
