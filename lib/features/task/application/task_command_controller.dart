import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../debt/domain/debt.dart';
import '../domain/task_failure.dart';
import '../domain/task_session.dart';

final taskCommandControllerProvider =
    NotifierProvider<TaskCommandController, AsyncValue<TaskCommandResult?>>(
      TaskCommandController.new,
    );

final class TaskCommandResult {
  const TaskCommandResult({required this.task, this.debt});

  final TaskSession task;
  final Debt? debt;
}

final class TaskCommandController
    extends Notifier<AsyncValue<TaskCommandResult?>> {
  bool _commandInFlight = false;

  @override
  AsyncValue<TaskCommandResult?> build() => const AsyncData(null);

  void clear() {
    if (!_commandInFlight) {
      state = const AsyncData(null);
    }
  }

  Future<bool> start({
    required String ownerUid,
    required String groupId,
    required String content,
    required int durationSeconds,
  }) {
    return _run(() async {
      final task = await ref
          .read(startTaskProvider)
          .call(
            ownerUid: ownerUid,
            groupId: groupId,
            content: content,
            durationSeconds: durationSeconds,
          );
      return TaskCommandResult(task: task);
    });
  }

  Future<bool> succeed({required String ownerUid, required String taskId}) {
    return _run(() async {
      final task = await ref
          .read(taskRepositoryProvider)
          .succeedTask(ownerUid: ownerUid, taskId: taskId);
      return TaskCommandResult(task: task);
    });
  }

  Future<bool> abort({required String ownerUid, required String taskId}) {
    return _run(() async {
      final result = await ref
          .read(taskRepositoryProvider)
          .failTaskAndCreateDebt(
            ownerUid: ownerUid,
            taskId: taskId,
            reason: TaskFailureReason.userAborted,
            failureEventId: ref
                .read(taskEventIdGeneratorProvider)
                .generateManualAbortId(taskId),
          );
      return TaskCommandResult(task: result.task, debt: result.debt);
    });
  }

  Future<bool> _run(Future<TaskCommandResult> Function() command) async {
    if (_commandInFlight) {
      return false;
    }
    _commandInFlight = true;
    state = const AsyncLoading();
    try {
      final result = await command();
      if (ref.mounted) {
        state = AsyncData(result);
      }
      return true;
    } on Object catch (error, stackTrace) {
      final failure = error is TaskFailure
          ? error
          : const TaskFailure(TaskFailureKind.unknown);
      if (ref.mounted) {
        state = AsyncError(failure, stackTrace);
      }
      return false;
    } finally {
      _commandInFlight = false;
    }
  }
}
