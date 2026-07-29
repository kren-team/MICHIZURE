import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/debt/application/contribution_controller.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/squat/application/squat_session_controller.dart';
import 'package:michizure/features/squat/domain/squat_detector.dart';

import '../../debt/support/fake_contribution_repository.dart';
import '../support/fake_squat_detector.dart';

const sessionId = 'session-12345678';

void main() {
  test('selected Debt accepted rep reaches Phase 8 exactly once', () async {
    final detector = FakeSquatDetector();
    final repository = FakeContributionRepository();
    final container = _container(detector, repository);
    addTearDown(() async {
      container.dispose();
      await detector.close();
    });
    final controller = container.read(squatSessionControllerProvider.notifier);
    container.read(contributionControllerProvider);
    await _settle();

    expect(await controller.start(debtId: 'debt-a', remainingReps: 3), isTrue);
    detector.emit(_rep(sequence: 1));
    detector.emit(_rep(sequence: 1));
    await _settle(10);

    expect(repository.requests, hasLength(1));
    final request = repository.requests.single;
    expect(request.debtId, 'debt-a');
    expect(request.squatSessionId, sessionId);
    expect(request.sequence, 1);
    expect(
      request.eventId,
      ContributionEventId.build(
        userId: 'alice',
        squatSessionId: sessionId,
        sequence: 1,
      ),
    );
    expect(request.acceptedReps, 1);
    expect(container.read(squatSessionControllerProvider).detectedReps, 1);
  });

  test('offline accepted rep converges into the Phase 8 Outbox', () async {
    final detector = FakeSquatDetector();
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
    final outbox = InMemoryContributionOutbox();
    final container = _container(detector, repository, outbox: outbox);
    addTearDown(() async {
      container.dispose();
      await detector.close();
    });
    final controller = container.read(squatSessionControllerProvider.notifier);
    container.read(contributionControllerProvider);
    await _settle();

    await controller.start(debtId: 'debt-a', remainingReps: 3);
    detector.emit(_rep(sequence: 1));
    await _settle(10);

    expect(outbox.entries, hasLength(1));
    expect(container.read(contributionControllerProvider).pendingCount, 1);
  });

  test('terminal selected Debt stops the fixed session', () async {
    final detector = FakeSquatDetector();
    final container = _container(detector, FakeContributionRepository());
    addTearDown(() async {
      container.dispose();
      await detector.close();
    });
    final controller = container.read(squatSessionControllerProvider.notifier);
    container.read(contributionControllerProvider);
    await _settle();
    await controller.start(debtId: 'debt-a', remainingReps: 1);

    await controller.stopForTerminalDebt(_terminalDebt());

    expect(detector.stops, [sessionId]);
    expect(container.read(squatSessionControllerProvider).isRunning, isFalse);
  });

  test('typed detector failure is retained without platform text', () async {
    final detector = FakeSquatDetector()
      ..failure = const SquatDetectorFailure(
        SquatDetectorFailureReason.cameraUnavailable,
      );
    final container = _container(detector, FakeContributionRepository());
    addTearDown(() async {
      container.dispose();
      await detector.close();
    });
    final controller = container.read(squatSessionControllerProvider.notifier);
    container.read(contributionControllerProvider);
    await _settle();

    expect(await controller.start(debtId: 'debt-a', remainingReps: 1), isFalse);
    expect(
      container.read(squatSessionControllerProvider).failure?.reason,
      SquatDetectorFailureReason.cameraUnavailable,
    );
  });

  test('cached remaining bounds accepted local reps', () async {
    final detector = FakeSquatDetector();
    final repository = FakeContributionRepository();
    final container = _container(detector, repository);
    addTearDown(() async {
      container.dispose();
      await detector.close();
    });
    final controller = container.read(squatSessionControllerProvider.notifier);
    container.read(contributionControllerProvider);
    await _settle();
    await controller.start(debtId: 'debt-a', remainingReps: 1);

    detector.emit(_rep(sequence: 1));
    detector.emit(_rep(sequence: 2));
    await _settle(10);

    expect(repository.requests, hasLength(1));
  });
}

ProviderContainer _container(
  FakeSquatDetector detector,
  FakeContributionRepository repository, {
  InMemoryContributionOutbox? outbox,
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWithValue(
        const AsyncData(AuthUser(id: 'alice')),
      ),
      squatDetectorProvider.overrideWithValue(detector),
      squatSessionIdGeneratorProvider.overrideWithValue(
        const FixedSquatSessionIdGenerator(sessionId),
      ),
      submitContributionProvider.overrideWithValue(
        SubmitContribution(repository, outbox ?? InMemoryContributionOutbox()),
      ),
    ],
  );
}

SquatRepCompleted _rep({required int sequence}) {
  return SquatRepCompleted(
    eventId: '$sessionId-$sequence',
    occurredAt: DateTime.utc(2026, 7, 30),
    squatSessionId: sessionId,
    sequence: sequence,
    detectorVersion: 'squat-v1',
    frameObservedElapsedMs: 1_000,
    uiEmittedElapsedMs: 1_100,
    analysisLatencyMs: 100,
  );
}

Debt _terminalDebt() {
  return Debt(
    id: 'debt-a',
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: 'debt-a',
    memberCountAtFailure: 1,
    repsPerMember: 10,
    totalReps: 10,
    completedReps: 10,
    status: DebtStatus.completed,
    createdAt: DateTime.utc(2026),
    lockExpiresAt: DateTime.utc(2026, 1, 1, 1),
    closedAt: DateTime.utc(2026, 1, 1, 0, 30),
    lastContributionAt: DateTime.utc(2026, 1, 1, 0, 30),
    lastContributionEventId: 'event-1',
  );
}

Future<void> _settle([int turns = 5]) async {
  for (var index = 0; index < turns; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
