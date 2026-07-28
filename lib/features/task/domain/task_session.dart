enum TaskSessionStatus {
  running('running'),
  succeeded('succeeded'),
  failed('failed');

  const TaskSessionStatus(this.wireValue);

  final String wireValue;

  static TaskSessionStatus? fromWireValue(String value) {
    for (final status in values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return null;
  }
}

enum TaskFailureReason {
  foreignAppForeground('foreign_app_foreground'),
  userAborted('user_aborted'),
  monitorCapabilityLost('monitor_capability_lost'),
  recoveryDetectedViolation('recovery_detected_violation'),
  debugDemo('debug_demo');

  const TaskFailureReason(this.wireValue);

  final String wireValue;

  static TaskFailureReason? fromWireValue(String value) {
    for (final reason in values) {
      if (reason.wireValue == value) {
        return reason;
      }
    }
    return null;
  }
}

final class TaskSession {
  const TaskSession({
    required this.id,
    required this.ownerUid,
    required this.groupId,
    required this.content,
    required this.durationSeconds,
    required this.startedAt,
    required this.serverRecordedAt,
    required this.expectedEndAt,
    required this.status,
    required this.endedAt,
    required this.failureReason,
    required this.failureEventId,
    required this.groupMemberCountAtFailure,
    required this.debtId,
    required this.lockDurationSeconds,
    required this.guardConfigVersion,
  });

  static const int schemaVersion = 1;
  static const int lockDurationSecondsMvp = 1800;
  static const int guardConfigVersionMvp = 1;

  final String id;
  final String ownerUid;
  final String groupId;
  final String content;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime serverRecordedAt;
  final DateTime expectedEndAt;
  final TaskSessionStatus status;
  final DateTime? endedAt;
  final TaskFailureReason? failureReason;
  final String? failureEventId;
  final int? groupMemberCountAtFailure;
  final String? debtId;
  final int lockDurationSeconds;
  final int guardConfigVersion;

  bool get isTerminal => status != TaskSessionStatus.running;

  Duration remainingAt(DateTime now) {
    if (isTerminal || !now.isBefore(expectedEndAt)) {
      return Duration.zero;
    }
    return expectedEndAt.difference(now);
  }

  bool deadlineReachedAt(DateTime now) => !now.isBefore(expectedEndAt);
}

final class TaskContentValidator {
  const TaskContentValidator._();

  static const int minimumLength = 1;
  static const int maximumLength = 100;
  static final RegExp _disallowedCharacters = RegExp(
    '[\\x00-\\x1F\\x7F-\\x9F\\u2028\\u2029]',
  );

  static String normalize(String value) => value.trim();

  static bool isValid(String value) {
    final normalized = normalize(value);
    final length = normalized.runes.length;
    return length >= minimumLength &&
        length <= maximumLength &&
        !_disallowedCharacters.hasMatch(normalized);
  }
}

final class TaskDurationValidator {
  const TaskDurationValidator._();

  static const int minimumSeconds = 60;
  static const int maximumSeconds = 10800;

  static bool isValidSeconds(int seconds) =>
      seconds >= minimumSeconds && seconds <= maximumSeconds;
}
