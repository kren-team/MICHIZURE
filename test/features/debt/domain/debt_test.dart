import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/domain/debt.dart';

void main() {
  test(
    'derives remaining reps and overdue state without event aggregation',
    () {
      final debt = _debt(completedReps: 20);

      expect(debt.remainingReps, 30);
      expect(debt.isOverdueAt(DateTime.utc(2026, 1, 1, 10, 29)), isFalse);
      expect(debt.isOverdueAt(DateTime.utc(2026, 1, 1, 10, 30)), isTrue);
    },
  );

  test('terminal debt is never treated as overdue', () {
    final debt = _debt(
      completedReps: 50,
      status: DebtStatus.completed,
      closedAt: DateTime.utc(2026, 1, 1, 10, 20),
    );

    expect(debt.isTerminal, isTrue);
    expect(debt.isOverdueAt(DateTime.utc(2026, 1, 1, 11)), isFalse);
  });
}

Debt _debt({
  int completedReps = 0,
  DebtStatus status = DebtStatus.active,
  DateTime? closedAt,
}) {
  return Debt(
    id: 'debt-1',
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: 'debt-1',
    memberCountAtFailure: 5,
    repsPerMember: 10,
    totalReps: 50,
    completedReps: completedReps,
    status: status,
    createdAt: DateTime.utc(2026, 1, 1, 10),
    lockExpiresAt: DateTime.utc(2026, 1, 1, 10, 30),
    closedAt: closedAt,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}
