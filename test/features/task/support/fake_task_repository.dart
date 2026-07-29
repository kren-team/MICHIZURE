import 'dart:async';

import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/task/domain/task_repository.dart';
import 'package:michizure/features/task/domain/task_session.dart';

final class FakeTaskRepository implements TaskRepository {
  TaskSession task = runningTaskFixture();
  Debt debt = debtFixture();
  Object? startError;
  Object? succeedError;
  Object? failError;
  Completer<void>? startCompleter;
  Completer<void>? succeedCompleter;
  Completer<void>? failCompleter;
  Stream<TaskSession?> taskStream = Stream.value(runningTaskFixture());
  int startCalls = 0;
  int succeedCalls = 0;
  int failCalls = 0;
  StartTaskRequest? lastStartRequest;
  String? lastFailureEventId;

  @override
  Stream<TaskSession?> watchTask(String taskId) => taskStream;

  @override
  Future<TaskSession> startTask(StartTaskRequest request) async {
    startCalls += 1;
    lastStartRequest = request;
    if (startError case final error?) {
      throw error;
    }
    await startCompleter?.future;
    return task;
  }

  @override
  Future<TaskSession> succeedTask({
    required String ownerUid,
    required String taskId,
  }) async {
    succeedCalls += 1;
    if (succeedError case final error?) {
      throw error;
    }
    await succeedCompleter?.future;
    return succeededTaskFixture();
  }

  @override
  Future<FailedTaskResult> failTaskAndCreateDebt({
    required String ownerUid,
    required String taskId,
    required TaskFailureReason reason,
    required String failureEventId,
  }) async {
    failCalls += 1;
    lastFailureEventId = failureEventId;
    if (failError case final error?) {
      throw error;
    }
    await failCompleter?.future;
    return FailedTaskResult(task: failedTaskFixture(), debt: debt);
  }
}

TaskSession runningTaskFixture({
  DateTime? startedAt,
  Duration duration = const Duration(minutes: 30),
}) {
  final start = startedAt ?? DateTime.utc(2026, 1, 1, 10);
  return TaskSession(
    id: 'task-1',
    ownerUid: 'alice',
    groupId: 'group-1',
    content: '勉強する',
    durationSeconds: duration.inSeconds,
    startedAt: start,
    serverRecordedAt: start,
    expectedEndAt: start.add(duration),
    status: TaskSessionStatus.running,
    endedAt: null,
    failureReason: null,
    failureEventId: null,
    groupMemberCountAtFailure: null,
    debtId: null,
    lockDurationSeconds: TaskSession.lockDurationSecondsMvp,
    guardConfigVersion: TaskSession.guardConfigVersionMvp,
  );
}

TaskSession succeededTaskFixture() {
  final running = runningTaskFixture();
  return TaskSession(
    id: running.id,
    ownerUid: running.ownerUid,
    groupId: running.groupId,
    content: running.content,
    durationSeconds: running.durationSeconds,
    startedAt: running.startedAt,
    serverRecordedAt: running.serverRecordedAt,
    expectedEndAt: running.expectedEndAt,
    status: TaskSessionStatus.succeeded,
    endedAt: running.expectedEndAt,
    failureReason: null,
    failureEventId: null,
    groupMemberCountAtFailure: null,
    debtId: null,
    lockDurationSeconds: running.lockDurationSeconds,
    guardConfigVersion: running.guardConfigVersion,
  );
}

TaskSession failedTaskFixture() {
  final running = runningTaskFixture();
  return TaskSession(
    id: running.id,
    ownerUid: running.ownerUid,
    groupId: running.groupId,
    content: running.content,
    durationSeconds: running.durationSeconds,
    startedAt: running.startedAt,
    serverRecordedAt: running.serverRecordedAt,
    expectedEndAt: running.expectedEndAt,
    status: TaskSessionStatus.failed,
    endedAt: running.startedAt.add(const Duration(minutes: 5)),
    failureReason: TaskFailureReason.userAborted,
    failureEventId: 'manual-task-1-fixed',
    groupMemberCountAtFailure: 5,
    debtId: running.id,
    lockDurationSeconds: running.lockDurationSeconds,
    guardConfigVersion: running.guardConfigVersion,
  );
}

Debt debtFixture() {
  final createdAt = DateTime.utc(2026, 1, 1, 10, 5);
  return Debt(
    id: 'task-1',
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: 'task-1',
    memberCountAtFailure: 5,
    repsPerMember: 10,
    totalReps: 50,
    completedReps: 0,
    status: DebtStatus.active,
    createdAt: createdAt,
    lockExpiresAt: createdAt.add(const Duration(minutes: 30)),
    closedAt: null,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}
