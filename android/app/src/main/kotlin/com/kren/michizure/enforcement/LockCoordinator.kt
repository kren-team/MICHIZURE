package com.kren.michizure.enforcement

import android.content.Context
import com.kren.michizure.monitoring.AndroidTaskGuardClock
import com.kren.michizure.monitoring.TaskGuardClock
import com.kren.michizure.persistence.LockObligationStore
import com.kren.michizure.persistence.LockStateStore
import com.kren.michizure.persistence.NativeTaskStore
import com.kren.michizure.persistence.NativeTaskRecord
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class LockCoordinator(
    private val obligationStore: LockStateStore,
    private val taskSnapshotSource: LockTaskSnapshotSource,
    private val packageSuspender: PackageSuspender,
    private val clock: TaskGuardClock,
    private val scheduler: LockDeadlineScheduler,
    private val reconciler: LockReconciler = LockReconciler(),
) {
    constructor(context: Context) : this(
        obligationStore = LockObligationStore(context),
        taskSnapshotSource = StoredLockTaskSnapshotSource(NativeTaskStore(context)),
        packageSuspender = AndroidPackageSuspender(context),
        clock = AndroidTaskGuardClock(context),
        scheduler = AndroidLockDeadlineScheduler(context),
    )

    suspend fun applyObligation(
        debtId: String,
        taskSessionId: String,
        createdWallMs: Long,
        expiresWallMs: Long,
    ): LockReconciliationResult = operationMutex.withLock {
        require(debtId.isNotBlank() && taskSessionId.isNotBlank())
        require(createdWallMs >= 0 && expiresWallMs >= createdWallMs)

        val existing = obligationStore.read().obligations[debtId]
        if (existing == null) {
            val task =
                taskSnapshotSource.readTask()
                    ?: throw LockCoordinatorException(
                        LockErrorCode.TASK_SNAPSHOT_MISSING,
                    )
            if (task.taskSessionId != taskSessionId) {
                throw LockCoordinatorException(
                    LockErrorCode.TASK_SNAPSHOT_MISSING,
                )
            }
            val now = clockSnapshot()
            val obligation =
                LockObligation(
                    debtId = debtId,
                    taskSessionId = taskSessionId,
                    packageNames = task.lockTargetsAtStart,
                    createdWallMs = createdWallMs,
                    expiresWallMs = expiresWallMs,
                    createdElapsedMs =
                        (now.elapsedMs - (now.wallMs - createdWallMs))
                            .coerceAtLeast(0),
                    expiresElapsedMs =
                        now.elapsedMs + (expiresWallMs - now.wallMs).coerceAtLeast(0),
                    bootCount = now.bootCount,
                )
            obligationStore.update { state ->
                val raced = state.obligations[debtId]
                if (raced != null) {
                    validateIdempotent(raced, obligation)
                    state
                } else {
                    state.copy(
                        obligations = state.obligations + (debtId to obligation),
                    )
                }
            }
        } else {
            if (existing.taskSessionId != taskSessionId ||
                existing.createdWallMs != createdWallMs ||
                existing.expiresWallMs != expiresWallMs
            ) {
                throw LockCoordinatorException(
                    LockErrorCode.NATIVE_STATE_CORRUPT,
                )
            }
        }
        reconcileLocked()
    }

    suspend fun resolveObligation(
        debtId: String,
        status: LockRemoteStatus,
    ): LockReconciliationResult = operationMutex.withLock {
        require(status != LockRemoteStatus.ACTIVE)
        obligationStore.update { state ->
            val obligation = state.obligations[debtId] ?: return@update state
            state.copy(
                obligations =
                    state.obligations +
                        (
                            debtId to
                                obligation.copy(
                                    remoteStatus = status,
                                    localState = LockLocalState.RELEASE_PENDING,
                                    lastErrorCode = null,
                                )
                            ),
            )
        }
        reconcileLocked()
    }

    suspend fun reconcile(): LockReconciliationResult =
        operationMutex.withLock { reconcileLocked() }

    suspend fun readState(): PersistedLockState = obligationStore.read()

    private suspend fun reconcileLocked(): LockReconciliationResult {
        val now = clockSnapshot()
        var state =
            obligationStore.update { current ->
                val expired =
                    current.obligations.mapValues { (_, obligation) ->
                        if (obligation.isExpiredAt(now)) {
                            obligation.copy(
                                remoteStatus = LockRemoteStatus.EXPIRED,
                                localState = LockLocalState.RELEASE_PENDING,
                                lastErrorCode = null,
                            )
                        } else {
                            obligation
                        }
                    }
                current.copy(obligations = expired)
            }
        val relevantPackages =
            state.ownedSuspensions +
                state.obligations.values.flatMap { it.packageNames }
        val actualResult = packageSuspender.querySuspended(relevantPackages)
        val plan =
            reconciler.plan(
                state = state,
                actualSuspendedPackages = actualResult.changedPackages,
                clock = now,
            )

        if (!packageSuspender.isDeviceOwner() &&
            (plan.packagesToApply.isNotEmpty() || plan.packagesToRelease.isNotEmpty())
        ) {
            state =
                obligationStore.update { current ->
                    current.copy(
                        obligations =
                            current.obligations.mapValues { (_, obligation) ->
                                if (obligation.isUnresolvedAt(now)) {
                                    obligation.copy(
                                        localState = LockLocalState.DEGRADED,
                                        lastErrorCode = LockErrorCode.NOT_DEVICE_OWNER,
                                    )
                                } else {
                                    obligation
                                }
                            },
                    )
                }
            scheduler.schedule(plan.nextDeadlineElapsedMs)
            throw LockCoordinatorException(LockErrorCode.NOT_DEVICE_OWNER)
        }

        val applyResult =
            packageSuspender.setSuspended(plan.packagesToApply, true)
        val releaseResult =
            packageSuspender.setSuspended(plan.packagesToRelease, false)
        val unavailable = actualResult.unavailablePackages
        val failedApply = applyResult.failedPackages + unavailable.intersect(plan.desiredPackages)
        val failedRelease = releaseResult.failedPackages
        val nextOwned =
            (state.ownedSuspensions + applyResult.changedPackages)
                .minus(releaseResult.changedPackages)
                .minus(unavailable)
        val effectiveAfter =
            actualResult.changedPackages +
                applyResult.changedPackages -
                releaseResult.changedPackages

        state =
            obligationStore.update { current ->
                current.copy(
                    ownedSuspensions = nextOwned,
                    obligations =
                        current.obligations.mapValues { (_, obligation) ->
                            val active = obligation.isUnresolvedAt(now)
                            val failures =
                                if (active) {
                                    obligation.packageNames.intersect(failedApply)
                                } else {
                                    obligation.packageNames.intersect(failedRelease)
                                }
                            val localState =
                                when {
                                    failures.isNotEmpty() -> LockLocalState.DEGRADED
                                    active &&
                                        effectiveAfter.containsAll(obligation.packageNames) ->
                                        LockLocalState.ENFORCED
                                    active -> LockLocalState.DEGRADED
                                    obligation.packageNames.any { it in nextOwned } ->
                                        LockLocalState.RELEASE_PENDING
                                    else -> LockLocalState.RELEASED
                                }
                            obligation.copy(
                                localState = localState,
                                failedPackages = failures,
                                lastErrorCode =
                                    when {
                                        failures.isEmpty() -> null
                                        active ->
                                            LockErrorCode.SUSPENSION_PARTIAL_FAILURE
                                        else ->
                                            LockErrorCode.UNSUSPENSION_PARTIAL_FAILURE
                                    },
                            )
                        },
                )
            }
        val refreshedPlan =
            reconciler.plan(
                state = state,
                actualSuspendedPackages = effectiveAfter,
                clock = now,
            )
        scheduler.schedule(refreshedPlan.nextDeadlineElapsedMs)
        return LockReconciliationResult(
            state = state,
            desiredPackages = refreshedPlan.desiredPackages,
            appliedPackages = applyResult.changedPackages,
            releasedPackages = releaseResult.changedPackages,
            failedPackages = failedApply + failedRelease,
            nextDeadlineWallMs = refreshedPlan.nextDeadlineWallMs,
        )
    }

    private fun clockSnapshot(): LockClockSnapshot {
        return LockClockSnapshot(
            wallMs = clock.wallTimeMs(),
            elapsedMs = clock.elapsedRealtimeMs(),
            bootCount = clock.bootCount(),
        )
    }

    private fun validateIdempotent(
        existing: LockObligation,
        incoming: LockObligation,
    ) {
        if (existing.taskSessionId != incoming.taskSessionId ||
            existing.packageNames != incoming.packageNames ||
            existing.createdWallMs != incoming.createdWallMs ||
            existing.expiresWallMs != incoming.expiresWallMs
        ) {
            throw LockCoordinatorException(LockErrorCode.NATIVE_STATE_CORRUPT)
        }
    }

    companion object {
        private val operationMutex = Mutex()
    }
}

class LockCoordinatorException(val code: String) : IllegalStateException(code)

fun interface LockTaskSnapshotSource {
    suspend fun readTask(): NativeTaskRecord?
}

private class StoredLockTaskSnapshotSource(
    private val store: NativeTaskStore,
) : LockTaskSnapshotSource {
    override suspend fun readTask(): NativeTaskRecord? = store.readTask()
}
