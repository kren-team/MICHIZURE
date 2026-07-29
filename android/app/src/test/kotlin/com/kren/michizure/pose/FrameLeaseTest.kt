package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class FrameLeaseTest {
    @Test
    fun oneFrameIsInFlightAndEveryCompletionClosesExactlyOnce() {
        val gate = FrameLeaseGate()
        var closeCount = 0
        val first = gate.tryAcquire { closeCount += 1 }

        assertNotNull(first)
        assertNull(gate.tryAcquire { closeCount += 1 })
        first!!.close()
        first.close()
        assertEquals(1, closeCount)

        val second = gate.tryAcquire { closeCount += 1 }
        assertNotNull(second)
        second!!.close()
        assertEquals(2, closeCount)
    }

    @Test
    fun releaseRecoversEvenWhenCloseCallbackThrows() {
        val gate = FrameLeaseGate()
        val first = gate.tryAcquire { error("close failure") }!!
        runCatching(first::close)

        assertNotNull(gate.tryAcquire {})
    }
}
