import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/application/notifying_task_repository.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';
import 'package:michizure/features/task/domain/task_session.dart';

import '../../task/support/fake_task_repository.dart';

void main() {
  test('publishes only after Debt creation succeeds', () async {
    final delegate = FakeTaskRepository();
    final notifications = _RecordingNotifications();
    final repository = NotifyingTaskRepository(delegate, notifications);

    final result = await repository.failTaskAndCreateDebt(
      ownerUid: 'alice',
      taskId: 'task-1',
      reason: TaskFailureReason.userAborted,
      failureEventId: 'event-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(result.debt.id, 'task-1');
    expect(notifications.debtCreatedIds, ['task-1']);
  });

  test('notification failure does not change Debt creation result', () async {
    final repository = NotifyingTaskRepository(
      FakeTaskRepository(),
      _FailingNotifications(),
    );

    final result = await repository.failTaskAndCreateDebt(
      ownerUid: 'alice',
      taskId: 'task-1',
      reason: TaskFailureReason.userAborted,
      failureEventId: 'event-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(result.debt.id, 'task-1');
  });
}

final class _FailingNotifications implements NotificationEventPublisher {
  @override
  Future<void> debtCreated(String debtId) async {
    throw StateError('unavailable');
  }

  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) async {}

  @override
  Future<void> debtCompleted(String debtId) async {}
}

final class _RecordingNotifications implements NotificationEventPublisher {
  final List<String> debtCreatedIds = [];

  @override
  Future<void> debtCreated(String debtId) async {
    debtCreatedIds.add(debtId);
  }

  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) async {}

  @override
  Future<void> debtCompleted(String debtId) async {}
}
