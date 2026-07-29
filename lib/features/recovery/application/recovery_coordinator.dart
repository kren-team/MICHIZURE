import '../../../core/time/clock.dart';
import '../../debt/application/submit_contribution.dart';
import '../../debt/domain/contribution.dart';
import '../../debt/domain/debt.dart';
import '../../debt/domain/debt_failure.dart';
import '../../debt/domain/debt_repository.dart';
import '../../enforcement/domain/app_lock.dart';
import '../../enforcement/domain/app_lock_repository.dart';
import '../../enforcement/domain/enforcement_failure.dart';
import '../../task/domain/native_task_guard.dart';
import '../../task/domain/task_failure.dart';
import '../../task/domain/task_repository.dart';
import '../domain/recovery.dart';

typedef RecoveryPhaseListener = void Function(RecoveryPhase phase);

final class RecoveryCoordinator {
  RecoveryCoordinator({
    required RecoveryAuthGateway authGateway,
    required RecoveryRemoteStore remoteStore,
    required TaskRepository taskRepository,
    required DebtRepository debtRepository,
    required NativeTaskGuard nativeTaskGuard,
    required AppLockRepository appLockRepository,
    required SubmitContribution submitContribution,
    required Clock clock,
  }) : this._(
         authGateway,
         remoteStore,
         taskRepository,
         debtRepository,
         nativeTaskGuard,
         appLockRepository,
         submitContribution,
         clock,
       );

  RecoveryCoordinator._(
    this._authGateway,
    this._remoteStore,
    this._taskRepository,
    this._debtRepository,
    this._nativeTaskGuard,
    this._appLockRepository,
    this._submitContribution,
    this._clock,
  );

  final RecoveryAuthGateway _authGateway;
  final RecoveryRemoteStore _remoteStore;
  final TaskRepository _taskRepository;
  final DebtRepository _debtRepository;
  final NativeTaskGuard _nativeTaskGuard;
  final AppLockRepository _appLockRepository;
  final SubmitContribution _submitContribution;
  final Clock _clock;

  Future<RecoveryReport>? _inFlight;

  Future<RecoveryReport> run(
    RecoveryTrigger trigger, {
    RecoveryPhaseListener? onPhase,
  }) {
    final current = _inFlight;
    if (current != null) {
      return current;
    }
    final future = _run(trigger, onPhase: onPhase);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<RecoveryReport> _run(
    RecoveryTrigger trigger, {
    RecoveryPhaseListener? onPhase,
  }) async {
    final startedAt = _clock.now().toUtc();
    final issues = <RecoveryIssue>[];
    final actions = <RecoveryAction>{};
    final metrics = _RecoveryMetrics();
    AppLockState? lockState;

    onPhase?.call(RecoveryPhase.checkingLocal);
    try {
      onPhase?.call(RecoveryPhase.enforcingLocks);
      lockState = await _appLockRepository.reconcile();
      actions.add(RecoveryAction.lockReconciled);
    } on Object catch (error) {
      issues.add(_lockIssue(error));
    }

    onPhase?.call(RecoveryPhase.restoringAuth);
    final RecoveryAuthResult auth;
    try {
      auth = await _authGateway.recoverSession();
    } on Object {
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.authTemporarilyUnavailable,
          RecoveryIssueSeverity.degraded,
        ),
      );
      return _report(trigger, startedAt, issues, actions, metrics);
    }
    switch (auth.status) {
      case RecoveryAuthStatus.signedOut:
        return _report(trigger, startedAt, issues, actions, metrics);
      case RecoveryAuthStatus.invalidCredentialSignedOut:
        actions.add(RecoveryAction.signedOutInvalidCredential);
        issues.add(
          const RecoveryIssue(
            RecoveryIssueKind.invalidCredentialSignedOut,
            RecoveryIssueSeverity.actionRequired,
          ),
        );
        return _report(trigger, startedAt, issues, actions, metrics);
      case RecoveryAuthStatus.temporarilyUnavailable:
        issues.add(
          const RecoveryIssue(
            RecoveryIssueKind.authTemporarilyUnavailable,
            RecoveryIssueSeverity.degraded,
          ),
        );
        return _report(trigger, startedAt, issues, actions, metrics);
      case RecoveryAuthStatus.authenticated:
        break;
    }
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) {
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.malformedRemoteState,
          RecoveryIssueSeverity.fatal,
        ),
      );
      return _report(trigger, startedAt, issues, actions, metrics);
    }

    onPhase?.call(RecoveryPhase.flushingNativeEvent);
    NativeTaskGuardState? nativeState;
    try {
      nativeState = await _nativeTaskGuard.getState();
      if (nativeState.hasPendingEvent) {
        actions.add(RecoveryAction.nativeEventReplayRequested);
      }
    } on Object catch (error) {
      issues.add(_nativeIssue(error));
    }

    onPhase?.call(RecoveryPhase.reconcilingRemote);
    RecoveryUserPointer? pointer;
    try {
      pointer = await _remoteStore.fetchUserPointer(userId);
      metrics.reads += 1;
      if (pointer != null && nativeState != null) {
        await _reconcileTask(
          userId: userId,
          pointer: pointer,
          nativeState: nativeState,
          issues: issues,
          actions: actions,
          metrics: metrics,
        );
      }
    } on Object catch (error) {
      issues.add(_remoteIssue(error));
    }

    if (lockState != null) {
      lockState = await _reconcileDebts(
        userId: userId,
        initialState: lockState,
        issues: issues,
        actions: actions,
        metrics: metrics,
      );
    }

    onPhase?.call(RecoveryPhase.flushingContributionOutbox);
    try {
      final deliveries = await _submitContribution.flushPending(userId);
      for (final delivery in deliveries) {
        metrics.reads += 3;
        if (delivery.commitResult?.disposition ==
            ContributionCommitDisposition.accepted) {
          metrics.writes += 3;
        }
      }
      final pendingCount = await _submitContribution.pendingCount(userId);
      if (deliveries.isNotEmpty) {
        actions.add(RecoveryAction.contributionFlushed);
      }
      if (pendingCount > 0 ||
          deliveries.any(
            (delivery) => delivery.status == ContributionSyncStatus.pending,
          )) {
        issues.add(
          const RecoveryIssue(
            RecoveryIssueKind.contributionPending,
            RecoveryIssueSeverity.degraded,
          ),
        );
      }
    } on Object catch (error) {
      issues.add(_contributionIssue(error));
    }

    return _report(trigger, startedAt, issues, actions, metrics);
  }

  Future<void> _reconcileTask({
    required String userId,
    required RecoveryUserPointer pointer,
    required NativeTaskGuardState nativeState,
    required List<RecoveryIssue> issues,
    required Set<RecoveryAction> actions,
    required _RecoveryMetrics metrics,
  }) async {
    final remoteTaskId = pointer.activeTaskSessionId;
    final nativeTaskId = nativeState.taskSessionId;

    if (nativeState.hasPendingEvent) {
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.pendingNativeEvent,
          RecoveryIssueSeverity.degraded,
        ),
      );
      return;
    }

    if (nativeTaskId != null && nativeTaskId != remoteTaskId) {
      final staleTask = await _remoteStore.fetchTask(nativeTaskId);
      metrics.reads += 1;
      if (staleTask == null || staleTask.isTerminal) {
        await _nativeTaskGuard.stop(nativeTaskId);
        actions.add(RecoveryAction.taskGuardStopped);
      } else {
        issues.add(
          const RecoveryIssue(
            RecoveryIssueKind.taskPointerMismatch,
            RecoveryIssueSeverity.actionRequired,
          ),
        );
        return;
      }
    }

    if (remoteTaskId == null) {
      return;
    }
    final task = await _remoteStore.fetchTask(remoteTaskId);
    metrics.reads += 1;
    if (task == null) {
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.taskMissing,
          RecoveryIssueSeverity.actionRequired,
        ),
      );
      return;
    }
    if (task.ownerUid != userId) {
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.taskPointerMismatch,
          RecoveryIssueSeverity.fatal,
        ),
      );
      return;
    }
    if (task.isTerminal) {
      if (nativeTaskId == task.id) {
        await _nativeTaskGuard.stop(task.id);
        actions.add(RecoveryAction.taskGuardStopped);
      }
      issues.add(
        const RecoveryIssue(
          RecoveryIssueKind.taskPointerMismatch,
          RecoveryIssueSeverity.degraded,
        ),
      );
      return;
    }
    if (task.deadlineReachedAt(_clock.now().toUtc())) {
      await _taskRepository.succeedTask(ownerUid: userId, taskId: task.id);
      metrics
        ..reads += 3
        ..writes += 2;
      await _nativeTaskGuard.stop(task.id);
      actions
        ..add(RecoveryAction.taskSucceeded)
        ..add(RecoveryAction.taskGuardStopped);
      return;
    }
    final result = await _nativeTaskGuard.start(task);
    if (result.taskSessionId != task.id || !result.isRunning) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.nativeStateCorrupt,
      );
    }
    actions.add(RecoveryAction.taskGuardStarted);
  }

  Future<AppLockState> _reconcileDebts({
    required String userId,
    required AppLockState initialState,
    required List<RecoveryIssue> issues,
    required Set<RecoveryAction> actions,
    required _RecoveryMetrics metrics,
  }) async {
    var state = initialState;
    final obligationIds = state.obligations
        .map((obligation) => obligation.debtId)
        .toSet();
    for (final obligation in state.obligations) {
      try {
        var debt = await _remoteStore.fetchDebt(obligation.debtId);
        metrics.reads += 1;
        if (debt == null) {
          issues.add(
            const RecoveryIssue(
              RecoveryIssueKind.debtMissing,
              RecoveryIssueSeverity.actionRequired,
            ),
          );
          continue;
        }
        if (debt.failedUserId != userId) {
          issues.add(
            const RecoveryIssue(
              RecoveryIssueKind.malformedRemoteState,
              RecoveryIssueSeverity.fatal,
            ),
          );
          continue;
        }
        if (debt.isOverdueAt(_clock.now().toUtc())) {
          debt = await _debtRepository.expireDebt(debt.id);
          metrics
            ..reads += 2
            ..writes += 1;
          actions.add(RecoveryAction.debtExpired);
        }
        if (debt.isTerminal) {
          state = await _appLockRepository.releaseObligation(
            debtId: debt.id,
            resolution: debt.status == DebtStatus.completed
                ? LockRemoteStatus.completed
                : LockRemoteStatus.expired,
          );
          actions.add(RecoveryAction.obligationReleased);
        }
      } on Object catch (error) {
        issues.add(_debtIssue(error));
      }
    }

    try {
      final activeDebts = await _remoteStore.fetchFailedUserActiveDebts(userId);
      metrics.reads += activeDebts.isEmpty ? 1 : activeDebts.length;
      for (final debt in activeDebts) {
        if (!obligationIds.contains(debt.id)) {
          issues.add(
            const RecoveryIssue(
              RecoveryIssueKind.lockObligationMissing,
              RecoveryIssueSeverity.actionRequired,
            ),
          );
        }
      }
    } on Object catch (error) {
      issues.add(_debtIssue(error));
    }

    try {
      state = await _appLockRepository.reconcile();
      actions.add(RecoveryAction.lockReconciled);
    } on Object catch (error) {
      issues.add(_lockIssue(error));
    }
    return state;
  }

  RecoveryReport _report(
    RecoveryTrigger trigger,
    DateTime startedAt,
    List<RecoveryIssue> issues,
    Set<RecoveryAction> actions,
    _RecoveryMetrics metrics,
  ) {
    return RecoveryReport(
      trigger: trigger,
      startedAt: startedAt,
      completedAt: _clock.now().toUtc(),
      issues: List.unmodifiable(issues),
      actions: Set.unmodifiable(actions),
      readCountEstimate: metrics.reads,
      writeCountEstimate: metrics.writes,
    );
  }
}

final class _RecoveryMetrics {
  int reads = 0;
  int writes = 0;
}

RecoveryIssue _lockIssue(Object error) {
  if (error is EnforcementFailure) {
    return switch (error.kind) {
      EnforcementFailureKind.notDeviceOwner => const RecoveryIssue(
        RecoveryIssueKind.capabilityUnavailable,
        RecoveryIssueSeverity.actionRequired,
      ),
      EnforcementFailureKind.nativeStateCorrupt => const RecoveryIssue(
        RecoveryIssueKind.nativeStateCorrupt,
        RecoveryIssueSeverity.actionRequired,
      ),
      _ => const RecoveryIssue(
        RecoveryIssueKind.lockRecoveryFailed,
        RecoveryIssueSeverity.degraded,
      ),
    };
  }
  return const RecoveryIssue(
    RecoveryIssueKind.lockRecoveryFailed,
    RecoveryIssueSeverity.degraded,
  );
}

RecoveryIssue _nativeIssue(Object error) {
  if (error is NativeTaskGuardFailure) {
    return switch (error.kind) {
      NativeTaskGuardFailureKind.nativeStateCorrupt => const RecoveryIssue(
        RecoveryIssueKind.nativeStateCorrupt,
        RecoveryIssueSeverity.actionRequired,
      ),
      NativeTaskGuardFailureKind.notDeviceOwner ||
      NativeTaskGuardFailureKind.usageAccessMissing ||
      NativeTaskGuardFailureKind.notificationPermissionMissing =>
        const RecoveryIssue(
          RecoveryIssueKind.capabilityUnavailable,
          RecoveryIssueSeverity.actionRequired,
        ),
      _ => const RecoveryIssue(
        RecoveryIssueKind.taskRecoveryFailed,
        RecoveryIssueSeverity.degraded,
      ),
    };
  }
  return const RecoveryIssue(
    RecoveryIssueKind.taskRecoveryFailed,
    RecoveryIssueSeverity.degraded,
  );
}

RecoveryIssue _remoteIssue(Object error) {
  if (error is RecoveryFailure) {
    return switch (error.kind) {
      RecoveryFailureKind.offline => const RecoveryIssue(
        RecoveryIssueKind.remoteUnavailable,
        RecoveryIssueSeverity.degraded,
      ),
      RecoveryFailureKind.malformedData => const RecoveryIssue(
        RecoveryIssueKind.malformedRemoteState,
        RecoveryIssueSeverity.actionRequired,
      ),
      _ => const RecoveryIssue(
        RecoveryIssueKind.remoteUnavailable,
        RecoveryIssueSeverity.degraded,
      ),
    };
  }
  if (error is TaskFailure) {
    return RecoveryIssue(
      RecoveryIssueKind.taskRecoveryFailed,
      error.kind == TaskFailureKind.invalidData
          ? RecoveryIssueSeverity.actionRequired
          : RecoveryIssueSeverity.degraded,
    );
  }
  return const RecoveryIssue(
    RecoveryIssueKind.unknown,
    RecoveryIssueSeverity.degraded,
  );
}

RecoveryIssue _debtIssue(Object error) {
  if (error is DebtFailure) {
    return RecoveryIssue(
      RecoveryIssueKind.debtRecoveryFailed,
      error.kind == DebtFailureKind.invalidData
          ? RecoveryIssueSeverity.actionRequired
          : RecoveryIssueSeverity.degraded,
    );
  }
  return _remoteIssue(error);
}

RecoveryIssue _contributionIssue(Object error) {
  if (error is ContributionFailure &&
      error.reason == ContributionRejectionReason.malformedData) {
    return const RecoveryIssue(
      RecoveryIssueKind.contributionRecoveryFailed,
      RecoveryIssueSeverity.actionRequired,
    );
  }
  return const RecoveryIssue(
    RecoveryIssueKind.contributionRecoveryFailed,
    RecoveryIssueSeverity.degraded,
  );
}
