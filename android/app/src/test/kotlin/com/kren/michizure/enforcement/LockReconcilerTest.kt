package com.kren.michizure.enforcement

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LockReconcilerTest {
    private val reconciler = LockReconciler()
    private val now = LockClockSnapshot(wallMs = 5_000, elapsedMs = 2_000, bootCount = 7)

    @Test
    fun overlappingObligationsKeepPackageUntilTheLastOneResolves() {
        val activeA = obligation("a", setOf("shared", "only.a"))
        val activeB = obligation("b", setOf("shared"))
        val initial =
            PersistedLockState(
                obligations = mapOf("a" to activeA, "b" to activeB),
                ownedSuspensions = setOf("shared", "only.a"),
            )

        val afterACompleted =
            reconciler.plan(
                state =
                    initial.copy(
                        obligations =
                            initial.obligations +
                                ("a" to activeA.copy(remoteStatus = LockRemoteStatus.COMPLETED)),
                    ),
                actualSuspendedPackages = initial.ownedSuspensions,
                clock = now,
            )

        assertEquals(setOf("shared"), afterACompleted.desiredPackages)
        assertEquals(setOf("only.a"), afterACompleted.packagesToRelease)
        assertTrue("shared" !in afterACompleted.packagesToRelease)
    }

    @Test
    fun lastResolvedObligationReleasesOnlyOwnedSuspensions() {
        val resolved =
            obligation("a", setOf("owned", "foreign")).copy(
                remoteStatus = LockRemoteStatus.COMPLETED,
            )
        val plan =
            reconciler.plan(
                state =
                    PersistedLockState(
                        obligations = mapOf("a" to resolved),
                        ownedSuspensions = setOf("owned"),
                    ),
                actualSuspendedPackages = setOf("owned", "foreign"),
                clock = now,
            )

        assertEquals(setOf("owned"), plan.packagesToRelease)
        assertTrue("foreign" !in plan.packagesToRelease)
    }

    @Test
    fun deadlineUsesElapsedTimeOnSameBootAndWallTimeAfterBoot() {
        val active = obligation("a", setOf("target"))
        val before =
            reconciler.plan(
                PersistedLockState(mapOf("a" to active)),
                emptySet(),
                now.copy(elapsedMs = active.expiresElapsedMs - 1),
            )
        val after =
            reconciler.plan(
                PersistedLockState(mapOf("a" to active)),
                emptySet(),
                now.copy(elapsedMs = active.expiresElapsedMs),
            )
        val rebootedAfter =
            reconciler.plan(
                PersistedLockState(mapOf("a" to active)),
                emptySet(),
                LockClockSnapshot(
                    wallMs = active.expiresWallMs,
                    elapsedMs = 10,
                    bootCount = active.bootCount + 1,
                ),
            )

        assertEquals(setOf("target"), before.desiredPackages)
        assertEquals(setOf("a"), after.expiredDebtIds)
        assertEquals(setOf("a"), rebootedAfter.expiredDebtIds)
    }

    @Test
    fun uninstalledDesiredPackageIsPlannedForReapply() {
        val active = obligation("a", setOf("target"))
        val plan =
            reconciler.plan(
                PersistedLockState(
                    obligations = mapOf("a" to active),
                    ownedSuspensions = setOf("target"),
                ),
                actualSuspendedPackages = emptySet(),
                clock = now,
            )

        assertEquals(setOf("target"), plan.packagesToApply)
    }

    private fun obligation(
        debtId: String,
        packages: Set<String>,
    ): LockObligation {
        return LockObligation(
            debtId = debtId,
            taskSessionId = "task-$debtId",
            packageNames = packages,
            createdWallMs = 4_000,
            expiresWallMs = 10_000,
            createdElapsedMs = 1_000,
            expiresElapsedMs = 7_000,
            bootCount = 7,
        )
    }
}
