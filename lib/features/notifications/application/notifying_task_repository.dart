import 'dart:async';

import '../../task/domain/task_repository.dart';
import '../../task/domain/task_session.dart';
import '../domain/push_notifications.dart';

final class NotifyingTaskRepository implements TaskRepository {
  NotifyingTaskRepository(this._delegate, this._notifications);

  final TaskRepository _delegate;
  final NotificationEventPublisher _notifications;

  @override
  Stream<TaskSession?> watchTask(String taskId) => _delegate.watchTask(taskId);

  @override
  Future<TaskSession> startTask(StartTaskRequest request) =>
      _delegate.startTask(request);

  @override
  Future<TaskSession> succeedTask({
    required String ownerUid,
    required String taskId,
  }) => _delegate.succeedTask(ownerUid: ownerUid, taskId: taskId);

  @override
  Future<FailedTaskResult> failTaskAndCreateDebt({
    required String ownerUid,
    required String taskId,
    required TaskFailureReason reason,
    required String failureEventId,
  }) async {
    final result = await _delegate.failTaskAndCreateDebt(
      ownerUid: ownerUid,
      taskId: taskId,
      reason: reason,
      failureEventId: failureEventId,
    );
    unawaited(_publishDebtCreated(result.debt.id));
    return result;
  }

  Future<void> _publishDebtCreated(String debtId) async {
    try {
      await _notifications.debtCreated(debtId);
    } on Object {
      // Notification delivery is never authoritative for Debt creation.
    }
  }
}
