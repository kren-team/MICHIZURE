package com.kren.michizure.enforcement

class LockReconciler {
    fun plan(
        state: PersistedLockState,
        actualSuspendedPackages: Set<String>,
        clock: LockClockSnapshot,
    ): LockReconcilePlan {
        val expiredDebtIds =
            state.obligations.values
                .filter { it.isExpiredAt(clock) }
                .mapTo(linkedSetOf()) { it.debtId }
        val desiredPackages =
            state.obligations.values
                .filter { it.debtId !in expiredDebtIds && it.isUnresolvedAt(clock) }
                .flatMapTo(linkedSetOf()) { it.packageNames }
        val packagesToApply = desiredPackages - actualSuspendedPackages
        val packagesToRelease =
            state.ownedSuspensions
                .intersect(actualSuspendedPackages)
                .minus(desiredPackages)
        val next =
            state.obligations.values
                .filter { it.debtId !in expiredDebtIds && it.isUnresolvedAt(clock) }
                .minByOrNull {
                    if (it.bootCount == clock.bootCount) {
                        it.expiresElapsedMs
                    } else {
                        clock.elapsedMs + (it.expiresWallMs - clock.wallMs).coerceAtLeast(0)
                    }
                }
        return LockReconcilePlan(
            desiredPackages = desiredPackages,
            packagesToApply = packagesToApply,
            packagesToRelease = packagesToRelease,
            expiredDebtIds = expiredDebtIds,
            nextDeadlineWallMs = next?.expiresWallMs,
            nextDeadlineElapsedMs =
                next?.let {
                    if (it.bootCount == clock.bootCount) {
                        it.expiresElapsedMs
                    } else {
                        clock.elapsedMs + (it.expiresWallMs - clock.wallMs).coerceAtLeast(0)
                    }
                },
        )
    }
}
