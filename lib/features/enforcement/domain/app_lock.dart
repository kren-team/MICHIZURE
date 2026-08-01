enum LockRemoteStatus {
  active('active'),
  completed('completed'),
  expired('expired');

  const LockRemoteStatus(this.wireValue);
  final String wireValue;
}

enum LockLocalState {
  applyPending('applyPending'),
  enforced('enforced'),
  degraded('degraded'),
  releasePending('releasePending'),
  released('released');

  const LockLocalState(this.wireValue);
  final String wireValue;
}

final class LockObligationRequest {
  const LockObligationRequest({
    required this.debtId,
    required this.taskSessionId,
    required this.createdAt,
    required this.expiresAt,
  });

  final String debtId;
  final String taskSessionId;
  final DateTime createdAt;
  final DateTime expiresAt;
}

final class LockObligationSummary {
  const LockObligationSummary({
    required this.debtId,
    required this.taskSessionId,
    required this.expiresAt,
    required this.remoteStatus,
    required this.localState,
    required this.targetCount,
    required this.enforcedCount,
    required this.failedCount,
    required this.errorCode,
  });

  final String debtId;
  final String taskSessionId;
  final DateTime expiresAt;
  final LockRemoteStatus remoteStatus;
  final LockLocalState localState;
  final int targetCount;
  final int enforcedCount;
  final int failedCount;
  final String? errorCode;

  bool get isUnresolved => remoteStatus == LockRemoteStatus.active;
}

final class AppLockState {
  const AppLockState({
    required this.obligations,
    required this.effectiveTargetCount,
    required this.ownedSuspensionCount,
    required this.appliedCount,
    required this.releasedCount,
    required this.failedCount,
    required this.nextDeadline,
  });

  final List<LockObligationSummary> obligations;
  final int effectiveTargetCount;
  final int ownedSuspensionCount;
  final int appliedCount;
  final int releasedCount;
  final int failedCount;
  final DateTime? nextDeadline;

  bool get hasActiveLock => effectiveTargetCount > 0;
  bool get isDegraded =>
      failedCount > 0 ||
      obligations.any((value) => value.localState == LockLocalState.degraded);
}
