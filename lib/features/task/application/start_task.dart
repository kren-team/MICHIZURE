import '../../enforcement/domain/device_control_repository.dart';
import '../domain/task_failure.dart';
import '../domain/task_repository.dart';
import '../domain/task_session.dart';

final class StartTask {
  const StartTask(this._taskRepository, this._deviceControlRepository);

  final TaskRepository _taskRepository;
  final DeviceControlRepository _deviceControlRepository;

  Future<TaskSession> call({
    required String ownerUid,
    required String groupId,
    required String content,
    required int durationSeconds,
  }) async {
    final normalizedContent = TaskContentValidator.normalize(content);
    if (!TaskContentValidator.isValid(normalizedContent)) {
      throw const TaskFailure(TaskFailureKind.invalidContent);
    }
    if (!TaskDurationValidator.isValidSeconds(durationSeconds)) {
      throw const TaskFailure(TaskFailureKind.invalidDuration);
    }
    if (ownerUid.isEmpty || groupId.isEmpty) {
      throw const TaskFailure(TaskFailureKind.groupRequired);
    }

    try {
      final capabilities = await _deviceControlRepository.getCapabilities();
      if (!capabilities.isManagedDemoReady) {
        throw const TaskFailure(TaskFailureKind.deviceNotReady);
      }
      final selectedPackages = await _deviceControlRepository
          .getSelectedPackageNames();
      if (selectedPackages.isEmpty) {
        throw const TaskFailure(TaskFailureKind.noLockTargets);
      }
    } on TaskFailure {
      rethrow;
    } on Object {
      throw const TaskFailure(TaskFailureKind.deviceNotReady);
    }

    return _taskRepository.startTask(
      StartTaskRequest(
        ownerUid: ownerUid,
        groupId: groupId,
        content: normalizedContent,
        durationSeconds: durationSeconds,
      ),
    );
  }
}
