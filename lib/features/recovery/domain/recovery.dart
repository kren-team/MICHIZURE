import '../../debt/domain/debt.dart';
import '../../task/domain/task_session.dart';

enum RecoveryTrigger {
  coldStart,
  authRestored,
  listenerReconnected,
  foreground,
  manualRetry,
}

enum RecoveryPhase {
  idle,
  checkingLocal,
  enforcingLocks,
  restoringAuth,
  flushingNativeEvent,
  reconcilingRemote,
  flushingContributionOutbox,
  ready,
  degraded,
  actionRequired,
  failed,
}

enum RecoveryIssueSeverity { degraded, actionRequired, fatal }

enum RecoveryIssueKind {
  authTemporarilyUnavailable,
  invalidCredentialSignedOut,
  nativeStateCorrupt,
  capabilityUnavailable,
  taskMissing,
  taskPointerMismatch,
  taskRecoveryFailed,
  pendingNativeEvent,
  lockRecoveryFailed,
  debtMissing,
  lockObligationMissing,
  debtRecoveryFailed,
  contributionPending,
  contributionRecoveryFailed,
  remoteUnavailable,
  malformedRemoteState,
  unknown,
}

final class RecoveryIssue {
  const RecoveryIssue(this.kind, this.severity);

  final RecoveryIssueKind kind;
  final RecoveryIssueSeverity severity;
}

final class RecoveryReport {
  const RecoveryReport({
    required this.trigger,
    required this.startedAt,
    required this.completedAt,
    required this.issues,
    required this.actions,
    required this.readCountEstimate,
    required this.writeCountEstimate,
  });

  final RecoveryTrigger trigger;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<RecoveryIssue> issues;
  final Set<RecoveryAction> actions;
  final int readCountEstimate;
  final int writeCountEstimate;

  RecoveryPhase get terminalPhase {
    if (issues.any((issue) => issue.severity == RecoveryIssueSeverity.fatal)) {
      return RecoveryPhase.failed;
    }
    if (issues.any(
      (issue) => issue.severity == RecoveryIssueSeverity.actionRequired,
    )) {
      return RecoveryPhase.actionRequired;
    }
    if (issues.isNotEmpty) {
      return RecoveryPhase.degraded;
    }
    return RecoveryPhase.ready;
  }
}

enum RecoveryAction {
  signedOutInvalidCredential,
  taskGuardStarted,
  taskGuardStopped,
  taskSucceeded,
  nativeEventReplayRequested,
  lockReconciled,
  obligationReleased,
  debtExpired,
  contributionFlushed,
}

enum RecoveryAuthStatus {
  signedOut,
  authenticated,
  invalidCredentialSignedOut,
  temporarilyUnavailable,
}

final class RecoveryAuthResult {
  const RecoveryAuthResult({required this.status, this.userId});

  final RecoveryAuthStatus status;
  final String? userId;
}

final class RecoveryUserPointer {
  const RecoveryUserPointer({required this.activeTaskSessionId});

  final String? activeTaskSessionId;
}

enum RecoveryFailureKind { offline, unauthorized, malformedData, unknown }

final class RecoveryFailure implements Exception {
  const RecoveryFailure(this.kind);

  final RecoveryFailureKind kind;

  @override
  String toString() => 'RecoveryFailure($kind)';
}

abstract interface class RecoveryAuthGateway {
  Future<RecoveryAuthResult> recoverSession();
}

abstract interface class RecoveryRemoteStore {
  Future<RecoveryUserPointer?> fetchUserPointer(String userId);

  Future<TaskSession?> fetchTask(String taskId);

  Future<Debt?> fetchDebt(String debtId);

  Future<List<Debt>> fetchFailedUserActiveDebts(String userId);
}
