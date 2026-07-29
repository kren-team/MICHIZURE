package com.kren.michizure.persistence

import com.kren.michizure.enforcement.LockLocalState
import com.kren.michizure.enforcement.LockObligation
import com.kren.michizure.enforcement.LockRemoteStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LockObligationCodecTest {
    @Test
    fun roundTripsUnicodeAndMultiplePackages() {
        val obligation =
            LockObligation(
                debtId = "負債-1",
                taskSessionId = "task-1",
                packageNames = setOf("social.app", "video.app"),
                createdWallMs = 100,
                expiresWallMs = 200,
                createdElapsedMs = 10,
                expiresElapsedMs = 110,
                bootCount = 3,
                remoteStatus = LockRemoteStatus.ACTIVE,
                localState = LockLocalState.DEGRADED,
                failedPackages = setOf("video.app"),
                lastErrorCode = "suspensionPartialFailure",
            )

        assertEquals(
            obligation,
            LockObligationCodec.decode(LockObligationCodec.encode(obligation)),
        )
    }

    @Test
    fun corruptRecordIsRejected() {
        assertThrows(LockObligationStoreException::class.java) {
            LockObligationCodec.decode("not-a-record")
        }
    }
}
