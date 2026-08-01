package com.kren.michizure.enforcement

enum class LockRemoteStatus(val wireValue: String) {
    ACTIVE("active"),
    COMPLETED("completed"),
    EXPIRED("expired"),
}

enum class LockLocalState(val wireValue: String) {
    APPLY_PENDING("applyPending"),
    ENFORCED("enforced"),
    DEGRADED("degraded"),
    RELEASE_PENDING("releasePending"),
    RELEASED("released"),
}

data class LockObligation(
    val debtId: String,
    val taskSessionId: String,
    val packageNames: Set<String>,
    val createdWallMs: Long,
    val expiresWallMs: Long,
    val createdElapsedMs: Long,
    val expiresElapsedMs: Long,
    val bootCount: Int,
    val remoteStatus: LockRemoteStatus = LockRemoteStatus.ACTIVE,
    val localState: LockLocalState = LockLocalState.APPLY_PENDING,
    val failedPackages: Set<String> = emptySet(),
    val lastErrorCode: String? = null,
) {
    fun isUnresolvedAt(clock: LockClockSnapshot): Boolean {
        if (remoteStatus != LockRemoteStatus.ACTIVE) {
            return false
        }
        return if (clock.bootCount == bootCount) {
            clock.elapsedMs < expiresElapsedMs
        } else {
            clock.wallMs < expiresWallMs
        }
    }

    fun isExpiredAt(clock: LockClockSnapshot): Boolean {
        return remoteStatus == LockRemoteStatus.ACTIVE && !isUnresolvedAt(clock)
    }
}

data class PersistedLockState(
    val obligations: Map<String, LockObligation> = emptyMap(),
    val ownedSuspensions: Set<String> = emptySet(),
)

data class LockClockSnapshot(
    val wallMs: Long,
    val elapsedMs: Long,
    val bootCount: Int,
)

data class LockReconcilePlan(
    val desiredPackages: Set<String>,
    val packagesToApply: Set<String>,
    val packagesToRelease: Set<String>,
    val expiredDebtIds: Set<String>,
    val nextDeadlineWallMs: Long?,
    val nextDeadlineElapsedMs: Long?,
)

data class PackageSuspensionResult(
    val requestedPackages: Set<String>,
    val changedPackages: Set<String>,
    val failedPackages: Set<String>,
    val unavailablePackages: Set<String> = emptySet(),
    val capabilityError: String? = null,
)

data class LockReconciliationResult(
    val state: PersistedLockState,
    val desiredPackages: Set<String>,
    val appliedPackages: Set<String>,
    val releasedPackages: Set<String>,
    val failedPackages: Set<String>,
    val nextDeadlineWallMs: Long?,
)

object LockErrorCode {
    const val NOT_DEVICE_OWNER = "notDeviceOwner"
    const val PACKAGE_NOT_INSTALLED = "packageNotInstalled"
    const val SUSPENSION_PARTIAL_FAILURE = "suspensionPartialFailure"
    const val UNSUSPENSION_PARTIAL_FAILURE = "unsuspensionPartialFailure"
    const val NATIVE_STATE_CORRUPT = "nativeStateCorrupt"
    const val TASK_SNAPSHOT_MISSING = "taskSnapshotMissing"
}
