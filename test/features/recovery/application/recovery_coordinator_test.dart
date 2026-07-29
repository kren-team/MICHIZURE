import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/core/time/clock.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/enforcement/domain/app_lock.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';
import 'package:michizure/features/recovery/application/recovery_coordinator.dart';
import 'package:michizure/features/recovery/domain/recovery.dart';
import 'package:michizure/features/task/domain/task_session.dart';

import '../../debt/support/fake_contribution_repository.dart';
import '../../debt/support/fake_debt_repository.dart';
import '../../enforcement/support/fake_app_lock_repository.dart';
import '../../task/support/fake_native_task_guard.dart';
import '../../task/support/fake_task_repository.dart';

void main() {
  group('RecoveryCoordinator', () {
    test(
      'cold start with no authenticated user reconciles local lock',
      () async {
        final fixture = RecoveryFixture(
          auth: const RecoveryAuthResult(status: RecoveryAuthStatus.signedOut),
        );

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(report.terminalPhase, RecoveryPhase.ready);
        expect(fixture.lock.reconcileCalls, 1);
        expect(fixture.remote.userPointerCalls, 0);
      },
    );

    test(
      'invalid credential converges to signed out without remote reads',
      () async {
        final fixture = RecoveryFixture(
          auth: const RecoveryAuthResult(
            status: RecoveryAuthStatus.invalidCredentialSignedOut,
          ),
        );

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(report.terminalPhase, RecoveryPhase.actionRequired);
        expect(
          report.actions,
          contains(RecoveryAction.signedOutInvalidCredential),
        );
        expect(fixture.remote.userPointerCalls, 0);
      },
    );

    test(
      'temporary auth outage keeps recovery degraded and does not mutate task',
      () async {
        final fixture = RecoveryFixture(
          auth: const RecoveryAuthResult(
            status: RecoveryAuthStatus.temporarilyUnavailable,
            userId: 'alice',
          ),
        );

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(report.terminalPhase, RecoveryPhase.degraded);
        expect(fixture.tasks.succeedCalls, 0);
        expect(fixture.native.stopCalls, 0);
      },
    );

    test('running remote task restores the native guard', () async {
      final fixture = RecoveryFixture.authenticated();
      fixture.remote
        ..pointer = const RecoveryUserPointer(activeTaskSessionId: 'task-1')
        ..tasks['task-1'] = runningTaskFixture();

      final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

      expect(report.terminalPhase, RecoveryPhase.ready);
      expect(fixture.native.startCalls, 1);
      expect(report.actions, contains(RecoveryAction.taskGuardStarted));
    });

    test(
      'deadline remote task uses canonical success path and stops guard',
      () async {
        final fixture = RecoveryFixture.authenticated(
          now: DateTime.utc(2026, 1, 1, 10, 31),
        );
        fixture.remote
          ..pointer = const RecoveryUserPointer(activeTaskSessionId: 'task-1')
          ..tasks['task-1'] = runningTaskFixture();
        fixture.native.activeTaskId = 'task-1';

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(fixture.tasks.succeedCalls, 1);
        expect(fixture.native.stopCalls, 1);
        expect(report.actions, contains(RecoveryAction.taskSucceeded));
      },
    );

    test(
      'pending native terminal event is replayed without racing success',
      () async {
        final fixture = RecoveryFixture.authenticated(
          now: DateTime.utc(2026, 1, 1, 10, 31),
        );
        fixture.remote.pointer = const RecoveryUserPointer(
          activeTaskSessionId: 'task-1',
        );
        fixture.native
          ..activeTaskId = 'task-1'
          ..hasPendingEvent = true;

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(fixture.tasks.succeedCalls, 0);
        expect(
          report.actions,
          contains(RecoveryAction.nativeEventReplayRequested),
        );
        expect(report.terminalPhase, RecoveryPhase.degraded);
      },
    );

    test('terminal remote task stops a stale native monitor', () async {
      final fixture = RecoveryFixture.authenticated();
      fixture.remote
        ..pointer = const RecoveryUserPointer(activeTaskSessionId: 'task-1')
        ..tasks['task-1'] = succeededTaskFixture();
      fixture.native.activeTaskId = 'task-1';

      final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

      expect(fixture.native.stopCalls, 1);
      expect(report.actions, contains(RecoveryAction.taskGuardStopped));
      expect(report.terminalPhase, RecoveryPhase.degraded);
    });

    test(
      'missing pointed Task is action required and guard is not invented',
      () async {
        final fixture = RecoveryFixture.authenticated();
        fixture.remote.pointer = const RecoveryUserPointer(
          activeTaskSessionId: 'missing-task',
        );

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(report.terminalPhase, RecoveryPhase.actionRequired);
        expect(fixture.native.startCalls, 0);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(RecoveryIssueKind.taskMissing),
        );
      },
    );

    test(
      'terminal Debt releases a stale obligation then reconciles union',
      () async {
        final fixture = RecoveryFixture.authenticated();
        final terminal = _completedDebt();
        fixture.lock.state = _lockState(terminal.id);
        fixture.remote
          ..pointer = const RecoveryUserPointer(activeTaskSessionId: null)
          ..debts[terminal.id] = terminal;

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(fixture.lock.releaseCalls, 1);
        expect(fixture.lock.lastReleasedDebtId, terminal.id);
        expect(report.actions, contains(RecoveryAction.obligationReleased));
      },
    );

    test(
      'active Debt without recoverable local snapshot is action required',
      () async {
        final fixture = RecoveryFixture.authenticated();
        fixture.remote
          ..pointer = const RecoveryUserPointer(activeTaskSessionId: null)
          ..activeDebts = [debtFixture()];

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(report.terminalPhase, RecoveryPhase.actionRequired);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(RecoveryIssueKind.lockObligationMissing),
        );
      },
    );

    test('pending Contribution remains durable while offline', () async {
      final fixture = RecoveryFixture.authenticated();
      fixture.remote.pointer = const RecoveryUserPointer(
        activeTaskSessionId: null,
      );
      fixture.contributions.failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
      await fixture.outbox.put(contributionRequest());

      final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

      expect(report.terminalPhase, RecoveryPhase.degraded);
      expect(fixture.outbox.entries, contains(contributionRequest().eventId));
    });

    test(
      'already-confirmed Contribution retry converges exactly once',
      () async {
        final fixture = RecoveryFixture.authenticated();
        fixture.remote.pointer = const RecoveryUserPointer(
          activeTaskSessionId: null,
        );
        final request = contributionRequest();
        final accepted = await fixture.contributions.submit(request);
        await fixture.outbox.put(request);

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(accepted.acceptedReps, 1);
        expect(fixture.contributions.committed, hasLength(1));
        expect(fixture.outbox.entries, isEmpty);
        expect(report.terminalPhase, RecoveryPhase.ready);
      },
    );

    test(
      'terminal Debt rejects pending Contribution and clears the outbox',
      () async {
        final fixture = RecoveryFixture.authenticated();
        fixture.remote.pointer = const RecoveryUserPointer(
          activeTaskSessionId: null,
        );
        fixture.contributions.failure = const ContributionFailure(
          ContributionRejectionReason.debtTerminal,
        );
        final request = contributionRequest();
        await fixture.outbox.put(request);

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(fixture.outbox.entries, isEmpty);
        expect(report.terminalPhase, RecoveryPhase.ready);
      },
    );

    test(
      'one native recovery failure does not prevent Outbox convergence',
      () async {
        final fixture = RecoveryFixture.authenticated();
        fixture.remote.pointer = const RecoveryUserPointer(
          activeTaskSessionId: null,
        );
        fixture.lock.error = const EnforcementFailure(
          EnforcementFailureKind.notDeviceOwner,
        );
        final request = contributionRequest();
        await fixture.outbox.put(request);

        final report = await fixture.coordinator.run(RecoveryTrigger.coldStart);

        expect(fixture.outbox.entries, isEmpty);
        expect(fixture.contributions.committed, hasLength(1));
        expect(report.terminalPhase, RecoveryPhase.actionRequired);
      },
    );

    test('duplicate concurrent triggers share one single-flight run', () async {
      final blocker = Completer<void>();
      final authGateway = FakeRecoveryAuthGateway(
        const RecoveryAuthResult(status: RecoveryAuthStatus.signedOut),
      )..blocker = blocker;
      final fixture = RecoveryFixture(authGateway: authGateway);

      final first = fixture.coordinator.run(RecoveryTrigger.coldStart);
      final second = fixture.coordinator.run(RecoveryTrigger.foreground);
      await Future<void>.delayed(Duration.zero);
      expect(authGateway.calls, 1);
      blocker.complete();

      expect(identical(await first, await second), isTrue);
      expect(fixture.lock.reconcileCalls, 1);
    });
  });
}

final class RecoveryFixture {
  RecoveryFixture({
    RecoveryAuthResult auth = const RecoveryAuthResult(
      status: RecoveryAuthStatus.authenticated,
      userId: 'alice',
    ),
    FakeRecoveryAuthGateway? authGateway,
    DateTime? now,
  }) : authGateway = authGateway ?? FakeRecoveryAuthGateway(auth),
       clock = FakeRecoveryClock(now ?? DateTime.utc(2026, 1, 1, 10, 10)) {
    coordinator = RecoveryCoordinator(
      authGateway: this.authGateway,
      remoteStore: remote,
      taskRepository: tasks,
      debtRepository: debts,
      nativeTaskGuard: native,
      appLockRepository: lock,
      submitContribution: SubmitContribution(contributions, outbox),
      clock: clock,
    );
  }

  factory RecoveryFixture.authenticated({DateTime? now}) {
    return RecoveryFixture(now: now);
  }

  final FakeRecoveryAuthGateway authGateway;
  final FakeRecoveryRemoteStore remote = FakeRecoveryRemoteStore();
  final FakeTaskRepository tasks = FakeTaskRepository();
  final FakeDebtRepository debts = FakeDebtRepository();
  final FakeNativeTaskGuard native = FakeNativeTaskGuard();
  final FakeAppLockRepository lock = FakeAppLockRepository();
  final FakeContributionRepository contributions = FakeContributionRepository();
  final InMemoryContributionOutbox outbox = InMemoryContributionOutbox();
  final FakeRecoveryClock clock;
  late final RecoveryCoordinator coordinator;
}

final class FakeRecoveryAuthGateway implements RecoveryAuthGateway {
  FakeRecoveryAuthGateway(this.result);

  final RecoveryAuthResult result;
  Completer<void>? blocker;
  int calls = 0;

  @override
  Future<RecoveryAuthResult> recoverSession() async {
    calls += 1;
    await blocker?.future;
    return result;
  }
}

final class FakeRecoveryRemoteStore implements RecoveryRemoteStore {
  RecoveryUserPointer? pointer;
  final Map<String, TaskSession?> tasks = {};
  final Map<String, Debt?> debts = {};
  List<Debt> activeDebts = [];
  int userPointerCalls = 0;

  @override
  Future<Debt?> fetchDebt(String debtId) async => debts[debtId];

  @override
  Future<List<Debt>> fetchFailedUserActiveDebts(String userId) async {
    return activeDebts;
  }

  @override
  Future<TaskSession?> fetchTask(String taskId) async => tasks[taskId];

  @override
  Future<RecoveryUserPointer?> fetchUserPointer(String userId) async {
    userPointerCalls += 1;
    return pointer;
  }
}

final class FakeRecoveryClock implements Clock {
  FakeRecoveryClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

Debt _completedDebt() {
  final active = debtFixture();
  return Debt(
    id: active.id,
    groupId: active.groupId,
    failedUserId: active.failedUserId,
    failedTaskSessionId: active.failedTaskSessionId,
    memberCountAtFailure: active.memberCountAtFailure,
    repsPerMember: active.repsPerMember,
    totalReps: active.totalReps,
    completedReps: active.totalReps,
    status: DebtStatus.completed,
    createdAt: active.createdAt,
    lockExpiresAt: active.lockExpiresAt,
    closedAt: active.createdAt.add(const Duration(minutes: 10)),
    lastContributionAt: active.createdAt.add(const Duration(minutes: 10)),
    lastContributionEventId: 'alice_session-12345678_50',
  );
}

AppLockState _lockState(String debtId) {
  return AppLockState(
    obligations: [
      LockObligationSummary(
        debtId: debtId,
        taskSessionId: debtId,
        expiresAt: DateTime.utc(2026, 1, 1, 10, 35),
        remoteStatus: LockRemoteStatus.active,
        localState: LockLocalState.enforced,
        targetCount: 1,
        enforcedCount: 1,
        failedCount: 0,
        errorCode: null,
      ),
    ],
    effectiveTargetCount: 1,
    ownedSuspensionCount: 1,
    appliedCount: 0,
    releasedCount: 0,
    failedCount: 0,
    nextDeadline: DateTime.utc(2026, 1, 1, 10, 35),
  );
}
