enum DebtStatus {
  active('active'),
  completed('completed'),
  expired('expired');

  const DebtStatus(this.wireValue);

  final String wireValue;

  static DebtStatus? fromWireValue(String value) {
    for (final status in values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return null;
  }
}

final class Debt {
  const Debt({
    required this.id,
    required this.groupId,
    required this.failedUserId,
    required this.failedTaskSessionId,
    required this.memberCountAtFailure,
    required this.repsPerMember,
    required this.totalReps,
    required this.completedReps,
    required this.status,
    required this.createdAt,
    required this.lockExpiresAt,
    required this.closedAt,
    required this.lastContributionAt,
    required this.lastContributionEventId,
  });

  static const int schemaVersion = 1;
  static const int repsPerMemberMvp = 10;

  final String id;
  final String groupId;
  final String failedUserId;
  final String failedTaskSessionId;
  final int memberCountAtFailure;
  final int repsPerMember;
  final int totalReps;
  final int completedReps;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime lockExpiresAt;
  final DateTime? closedAt;
  final DateTime? lastContributionAt;
  final String? lastContributionEventId;

  int get remainingReps {
    final remaining = totalReps - completedReps;
    return remaining < 0 ? 0 : remaining;
  }
}
