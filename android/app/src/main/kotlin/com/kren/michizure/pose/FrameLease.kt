package com.kren.michizure.pose

import java.util.concurrent.atomic.AtomicBoolean

class FrameLeaseGate {
    private val inFlight = AtomicBoolean(false)

    fun tryAcquire(closeFrame: () -> Unit): FrameLease? {
        if (!inFlight.compareAndSet(false, true)) return null
        return FrameLease {
            try {
                closeFrame()
            } finally {
                inFlight.set(false)
            }
        }
    }
}

class FrameLease internal constructor(
    private val release: () -> Unit,
) : AutoCloseable {
    private val closed = AtomicBoolean(false)

    override fun close() {
        if (closed.compareAndSet(false, true)) release()
    }
}
