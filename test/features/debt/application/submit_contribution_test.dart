import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';

import '../support/fake_contribution_repository.dart';

void main() {
  test('persists before delivery and removes a confirmed event', () async {
    final repository = FakeContributionRepository();
    final outbox = InMemoryContributionOutbox();
    final useCase = SubmitContribution(repository, outbox);
    final request = contributionRequest();

    final delivery = await useCase.recordAcceptedRep(request);

    expect(delivery.status, ContributionSyncStatus.confirmed);
    expect(delivery.commitResult?.acceptedReps, 1);
    expect(repository.requests, [request]);
    expect(outbox.entries, isEmpty);
  });

  test('publishes an accepted Contribution but not its duplicate', () async {
    final repository = FakeContributionRepository();
    final outbox = InMemoryContributionOutbox();
    final notifications = _RecordingNotifications();
    final useCase = SubmitContribution(repository, outbox, notifications);
    final request = contributionRequest();

    await useCase.recordAcceptedRep(request);
    await useCase.recordAcceptedRep(request);
    await Future<void>.delayed(Duration.zero);

    expect(notifications.contributions, [(request.debtId, request.eventId)]);
  });

  test('publishes Debt completion after the completing Contribution', () async {
    final repository = FakeContributionRepository()..completesDebt = true;
    final notifications = _RecordingNotifications();
    final request = contributionRequest();
    final useCase = SubmitContribution(
      repository,
      InMemoryContributionOutbox(),
      notifications,
    );

    await useCase.recordAcceptedRep(request);
    await Future<void>.delayed(Duration.zero);

    expect(notifications.completedDebtIds, [request.debtId]);
  });

  test(
    'notification failure does not change a confirmed Contribution',
    () async {
      final useCase = SubmitContribution(
        FakeContributionRepository(),
        InMemoryContributionOutbox(),
        _FailingNotifications(),
      );

      final delivery = await useCase.recordAcceptedRep(contributionRequest());
      await Future<void>.delayed(Duration.zero);

      expect(delivery.status, ContributionSyncStatus.confirmed);
    },
  );

  test('duplicate event is confirmed without a second count', () async {
    final repository = FakeContributionRepository();
    final outbox = InMemoryContributionOutbox();
    final useCase = SubmitContribution(repository, outbox);
    final request = contributionRequest();

    await useCase.recordAcceptedRep(request);
    final duplicate = await useCase.recordAcceptedRep(request);

    expect(duplicate.status, ContributionSyncStatus.confirmed);
    expect(duplicate.commitResult?.isDuplicate, isTrue);
    expect(duplicate.commitResult?.acceptedReps, 0);
    expect(repository.committed, hasLength(1));
  });

  test('offline event remains pending and is confirmed by retry', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
    final outbox = InMemoryContributionOutbox();
    final useCase = SubmitContribution(repository, outbox);
    final request = contributionRequest();

    final pending = await useCase.recordAcceptedRep(request);
    expect(pending.status, ContributionSyncStatus.pending);
    expect(outbox.entries, contains(request.eventId));

    repository.failure = null;
    final retried = await useCase.flushPending(request.userId);
    expect(retried.single.status, ContributionSyncStatus.confirmed);
    expect(outbox.entries, isEmpty);
  });

  test('terminal Debt rejects and removes the pending event', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.debtTerminal,
      );
    final outbox = InMemoryContributionOutbox();
    final useCase = SubmitContribution(repository, outbox);

    final delivery = await useCase.recordAcceptedRep(contributionRequest());

    expect(delivery.status, ContributionSyncStatus.rejected);
    expect(delivery.failure?.reason, ContributionRejectionReason.debtTerminal);
    expect(outbox.entries, isEmpty);
  });

  test('flush preserves ordering and stops after an offline event', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
    final outbox = InMemoryContributionOutbox();
    final first = contributionRequest(sequence: 1);
    final second = contributionRequest(sequence: 2);
    await outbox.put(second);
    await outbox.put(first);
    final useCase = SubmitContribution(repository, outbox);

    final deliveries = await useCase.flushPending(first.userId);

    expect(deliveries, hasLength(1));
    expect(repository.requests.single.eventId, first.eventId);
    expect(outbox.entries, hasLength(2));
  });

  test('concurrent recovery flushes share one event delivery', () async {
    final repository = FakeContributionRepository();
    final outbox = InMemoryContributionOutbox();
    final request = contributionRequest();
    await outbox.put(request);
    final useCase = SubmitContribution(repository, outbox);

    final first = useCase.flushPending(request.userId);
    final second = useCase.flushPending(request.userId);
    final results = await Future.wait([first, second]);

    expect(repository.requests, [request]);
    expect(results[0].single.status, ContributionSyncStatus.confirmed);
    expect(results[1].single.status, ContributionSyncStatus.confirmed);
    expect(outbox.entries, isEmpty);
  });
}

final class _RecordingNotifications implements NotificationEventPublisher {
  final List<(String, String)> contributions = [];
  final List<String> completedDebtIds = [];

  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) async {
    contributions.add((debtId, contributionId));
  }

  @override
  Future<void> debtCompleted(String debtId) async {
    completedDebtIds.add(debtId);
  }

  @override
  Future<void> debtCreated(String debtId) async {}
}

final class _FailingNotifications implements NotificationEventPublisher {
  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) async {
    throw StateError('unavailable');
  }

  @override
  Future<void> debtCompleted(String debtId) async {
    throw StateError('unavailable');
  }

  @override
  Future<void> debtCreated(String debtId) async {
    throw StateError('unavailable');
  }
}
