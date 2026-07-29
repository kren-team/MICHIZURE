package com.kren.michizure.enforcement

import com.kren.michizure.monitoring.TaskGuardClock
import com.kren.michizure.persistence.LockStateStore
import com.kren.michizure.persistence.NativeTaskRecord
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LockCoordinatorTest {
    private val store = InMemoryLockStateStore()
    private val suspender = FakePackageSuspender()
    private val clock = FakeLockClock()
    private val scheduler = FakeLockScheduler()

    @Test
    fun applyPersistsBeforeSuspensionAndDuplicateDoesNotDuplicateObligation() =
        runBlocking {
            suspender.beforeChange = {
                assertTrue("debt-a" in store.state.obligations)
            }
            val coordinator = coordinator(setOf("social.app"))

            coordinator.applyObligation("debt-a", "task-a", 1_000, 20_000)
            coordinator.applyObligation("debt-a", "task-a", 1_000, 20_000)

            assertEquals(1, store.state.obligations.size)
            assertEquals(setOf("social.app"), store.state.ownedSuspensions)
            assertEquals(1, suspender.applyCalls)
        }

    @Test
    fun partialFailureIsPersistedAsDegraded() = runBlocking {
        suspender.failOnApply = setOf("video.app")
        val coordinator = coordinator(setOf("social.app", "video.app"))

        val result =
            coordinator.applyObligation("debt-a", "task-a", 1_000, 20_000)

        val obligation = result.state.obligations.getValue("debt-a")
        assertEquals(LockLocalState.DEGRADED, obligation.localState)
        assertEquals(setOf("video.app"), obligation.failedPackages)
        assertEquals(setOf("social.app"), result.state.ownedSuspensions)
    }

    @Test
    fun overlappingDebtsReleaseOnlyAfterLastResolution() = runBlocking {
        val coordinatorA = coordinator(setOf("shared.app"), taskId = "task-a")
        coordinatorA.applyObligation("debt-a", "task-a", 1_000, 20_000)
        val coordinatorB = coordinator(setOf("shared.app"), taskId = "task-b")
        coordinatorB.applyObligation("debt-b", "task-b", 1_000, 20_000)

        coordinatorA.resolveObligation("debt-a", LockRemoteStatus.COMPLETED)
        assertTrue("shared.app" in suspender.suspended)
        assertEquals(0, suspender.releaseCalls)

        coordinatorA.resolveObligation("debt-b", LockRemoteStatus.COMPLETED)
        assertTrue("shared.app" !in suspender.suspended)
        assertEquals(1, suspender.releaseCalls)
    }

    @Test
    fun expirationReleasesOfflineUsingAbsoluteDeadline() = runBlocking {
        val coordinator = coordinator(setOf("social.app"))
        coordinator.applyObligation("debt-a", "task-a", 1_000, 20_000)
        clock.wall = 20_000
        clock.elapsed = 21_000

        val result = coordinator.reconcile()

        assertEquals(
            LockRemoteStatus.EXPIRED,
            result.state.obligations.getValue("debt-a").remoteStatus,
        )
        assertTrue(result.state.ownedSuspensions.isEmpty())
        assertEquals(null, scheduler.deadline)
    }

    @Test
    fun deviceOwnerLossPreservesObligationForRetry() = runBlocking {
        suspender.deviceOwner = false
        val coordinator = coordinator(setOf("social.app"))

        val error =
            assertThrows(LockCoordinatorException::class.java) {
                runBlocking {
                    coordinator.applyObligation(
                        "debt-a",
                        "task-a",
                        1_000,
                        20_000,
                    )
                }
            }

        assertEquals(LockErrorCode.NOT_DEVICE_OWNER, error.code)
        assertEquals(
            LockLocalState.DEGRADED,
            store.state.obligations.getValue("debt-a").localState,
        )
    }

    @Test
    fun processRecreationAndPackageReinstallConverge() = runBlocking {
        coordinator(setOf("social.app"))
            .applyObligation("debt-a", "task-a", 1_000, 20_000)
        suspender.suspended.clear()

        val recreated = coordinator(setOf("social.app"))
        recreated.reconcile()

        assertTrue("social.app" in suspender.suspended)
        assertEquals(2, suspender.applyCalls)
    }

    @Test
    fun staleOwnedRecordIsRemovedWhenOsNoLongerReportsSuspension() = runBlocking {
        store.state =
            PersistedLockState(
                ownedSuspensions = setOf("stale.app"),
            )

        val result = coordinator(setOf("unused.app")).reconcile()

        assertTrue(result.state.ownedSuspensions.isEmpty())
        assertEquals(0, suspender.releaseCalls)
    }

    @Test
    fun packageUninstallStaysDegradedAndReinstallIsResuspended() = runBlocking {
        val coordinator = coordinator(setOf("social.app"))
        coordinator.applyObligation("debt-a", "task-a", 1_000, 20_000)
        suspender.unavailable = setOf("social.app")
        suspender.suspended.clear()

        val uninstalled = coordinator.reconcile()

        assertEquals(
            LockLocalState.DEGRADED,
            uninstalled.state.obligations.getValue("debt-a").localState,
        )
        assertTrue(uninstalled.state.ownedSuspensions.isEmpty())

        suspender.unavailable = emptySet()
        val reinstalled = coordinator.reconcile()

        assertEquals(
            LockLocalState.ENFORCED,
            reinstalled.state.obligations.getValue("debt-a").localState,
        )
        assertTrue("social.app" in reinstalled.state.ownedSuspensions)
    }

    private fun coordinator(
        packages: Set<String>,
        taskId: String = "task-a",
    ): LockCoordinator {
        val task =
            NativeTaskRecord(
                taskSessionId = taskId,
                startedWallMs = 1_000,
                expectedEndWallMs = 10_000,
                startedElapsedMs = 1_000,
                expectedEndElapsedMs = 10_000,
                bootCount = 1,
                guardConfigVersion = 1,
                lockTargetsAtStart = packages,
            )
        return LockCoordinator(
            obligationStore = store,
            taskSnapshotSource = LockTaskSnapshotSource { task },
            packageSuspender = suspender,
            clock = clock,
            scheduler = scheduler,
        )
    }
}

private class InMemoryLockStateStore : LockStateStore {
    var state = PersistedLockState()

    override suspend fun read(): PersistedLockState = state

    override suspend fun update(
        transform: (PersistedLockState) -> PersistedLockState,
    ): PersistedLockState {
        state = transform(state)
        return state
    }
}

private class FakePackageSuspender : PackageSuspender {
    var deviceOwner = true
    var failOnApply: Set<String> = emptySet()
    var unavailable: Set<String> = emptySet()
    var beforeChange: (() -> Unit)? = null
    val suspended = linkedSetOf<String>()
    var applyCalls = 0
    var releaseCalls = 0

    override fun isDeviceOwner(): Boolean = deviceOwner

    override fun querySuspended(packageNames: Set<String>): PackageSuspensionResult {
        return PackageSuspensionResult(
            requestedPackages = packageNames,
            changedPackages = suspended.intersect(packageNames),
            failedPackages = emptySet(),
            unavailablePackages = unavailable.intersect(packageNames),
        )
    }

    override fun setSuspended(
        packageNames: Set<String>,
        suspended: Boolean,
    ): PackageSuspensionResult {
        if (packageNames.isEmpty()) {
            return PackageSuspensionResult(emptySet(), emptySet(), emptySet())
        }
        beforeChange?.invoke()
        val failed =
            if (suspended) {
                packageNames.intersect(failOnApply + unavailable)
            } else {
                emptySet()
            }
        val changed = packageNames - failed
        if (suspended) {
            applyCalls += 1
            this.suspended += changed
        } else {
            releaseCalls += 1
            this.suspended -= changed
        }
        return PackageSuspensionResult(packageNames, changed, failed)
    }
}

private class FakeLockClock : TaskGuardClock {
    var wall = 2_000L
    var elapsed = 3_000L
    var boot = 1

    override fun wallTimeMs(): Long = wall

    override fun elapsedRealtimeMs(): Long = elapsed

    override fun bootCount(): Int = boot
}

private class FakeLockScheduler : LockDeadlineScheduler {
    var deadline: Long? = null

    override fun schedule(nextDeadlineElapsedMs: Long?) {
        deadline = nextDeadlineElapsedMs
    }
}
