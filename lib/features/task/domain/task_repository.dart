import '../../debt/domain/debt.dart';
import 'task_session.dart';

final class StartTaskRequest {
  const StartTaskRequest({
    required this.ownerUid,
    required this.groupId,
    required this.content,
    required this.durationSeconds,
  });

  final String ownerUid;
  final String groupId;
  final String content;
  final int durationSeconds;
}

final class FailedTaskResult {
  const FailedTaskResult({required this.task, required this.debt});

  final TaskSession task;
  final Debt debt;
}

abstract interface class TaskRepository {
  Stream<TaskSession?> watchTask(String taskId);

  Future<TaskSession> startTask(StartTaskRequest request);

  Future<TaskSession> succeedTask({
    required String ownerUid,
    required String taskId,
  });

  Future<FailedTaskResult> failTaskAndCreateDebt({
    required String ownerUid,
    required String taskId,
    required TaskFailureReason reason,
    required String failureEventId,
  });
}
