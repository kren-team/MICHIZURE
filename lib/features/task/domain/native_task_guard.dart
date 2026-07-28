import 'task_session.dart';

enum NativeTaskEventType { taskFailed, deadlineReached }

enum NativeTaskGuardFailureKind {
  channelContractMismatch,
  notDeviceOwner,
  usageAccessMissing,
  notificationPermissionMissing,
  foregroundServiceStartDenied,
  nativeStateCorrupt,
  nativeUnavailable,
  timeout,
  invalidData,
  unsupportedPlatform,
  unknown,
}

final class NativeTaskGuardFailure implements Exception {
  const NativeTaskGuardFailure(this.kind);

  final NativeTaskGuardFailureKind kind;

  @override
  String toString() => 'NativeTaskGuardFailure($kind)';
}

final class NativeTaskEvent {
  const NativeTaskEvent({
    required this.eventId,
    required this.taskSessionId,
    required this.type,
    required this.occurredAt,
    required this.failureReason,
  });

  final String eventId;
  final String taskSessionId;
  final NativeTaskEventType type;
  final DateTime occurredAt;
  final TaskFailureReason? failureReason;
}

final class NativeTaskGuardState {
  const NativeTaskGuardState({
    required this.taskSessionId,
    required this.isRunning,
    required this.hasPendingEvent,
  });

  final String? taskSessionId;
  final bool isRunning;
  final bool hasPendingEvent;
}

abstract interface class NativeTaskGuard {
  Stream<NativeTaskEvent> watchEvents();

  Future<NativeTaskGuardState> start(TaskSession task);

  Future<void> stop(String taskSessionId);

  Future<NativeTaskGuardState> getState();

  Future<bool> acknowledge(String eventId);
}
