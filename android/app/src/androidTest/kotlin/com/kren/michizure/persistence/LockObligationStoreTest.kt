package com.kren.michizure.persistence

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.kren.michizure.enforcement.LockObligation
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LockObligationStoreTest {
    @Test
    fun obligationAndOwnedSuspensionsSurviveStoreRecreation() {
        runBlocking {
            val context = ApplicationProvider.getApplicationContext<Context>()
            val debtId = "test-${System.nanoTime()}"
            val obligation =
                LockObligation(
                    debtId = debtId,
                    taskSessionId = "task-$debtId",
                    packageNames = setOf("example.target"),
                    createdWallMs = 100,
                    expiresWallMs = 200,
                    createdElapsedMs = 10,
                    expiresElapsedMs = 110,
                    bootCount = 1,
                )
            val first = LockObligationStore(context)
            first.update {
                it.copy(
                    obligations = it.obligations + (debtId to obligation),
                    ownedSuspensions = it.ownedSuspensions + "example.target",
                )
            }

            val restored = LockObligationStore(context).read()
            val bootRestored = DeviceProtectedLockStateStore(context).read()

            assertEquals(obligation, restored.obligations[debtId])
            assertEquals(true, "example.target" in restored.ownedSuspensions)
            assertEquals(obligation, bootRestored.obligations[debtId])
            assertEquals(true, "example.target" in bootRestored.ownedSuspensions)
            first.update {
                it.copy(
                    obligations = it.obligations - debtId,
                    ownedSuspensions = it.ownedSuspensions - "example.target",
                )
            }
        }
    }
}
