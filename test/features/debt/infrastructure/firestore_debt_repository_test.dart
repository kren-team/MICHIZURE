import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/domain/debt_failure.dart';
import 'package:michizure/features/debt/infrastructure/firestore_debt_repository.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1, 10);

  test('maps valid active, completed and expired debts', () {
    final active = debtFromFirestore('task-1', _debtData(createdAt));
    final completed = debtFromFirestore(
      'task-2',
      _debtData(
        createdAt,
        taskId: 'task-2',
        status: 'completed',
        completedReps: 50,
        closedAt: createdAt.add(const Duration(minutes: 10)),
      ),
    );
    final expired = debtFromFirestore(
      'task-3',
      _debtData(
        createdAt,
        taskId: 'task-3',
        status: 'expired',
        closedAt: createdAt.add(const Duration(minutes: 30)),
      ),
    );

    expect(active.remainingReps, 50);
    expect(completed.status, DebtStatus.completed);
    expect(expired.status, DebtStatus.expired);
  });

  test('keeps Unicode member identity outside the Debt document', () {
    final summary = debtContributionSummaryFromFirestore('奏', {
      'userId': '奏',
      'totalReps': 7,
      'lastEventId': 'event-1',
      'lastContributedAt': Timestamp.fromDate(createdAt),
      'schemaVersion': 1,
    });

    expect(summary.userId, '奏');
    expect(summary.totalReps, 7);
  });

  test(
    'rejects unknown fields, invalid aggregate and invalid terminal shape',
    () {
      expect(
        () => debtFromFirestore('task-1', {
          ..._debtData(createdAt),
          'packageName': 'private.package',
        }),
        throwsA(isA<DebtFailure>()),
      );
      expect(
        () => debtFromFirestore(
          'task-1',
          _debtData(createdAt, completedReps: 51),
        ),
        throwsA(isA<DebtFailure>()),
      );
      expect(
        () => debtFromFirestore(
          'task-1',
          _debtData(createdAt, status: 'completed', completedReps: 50),
        ),
        throwsA(isA<DebtFailure>()),
      );
    },
  );
}

Map<String, Object?> _debtData(
  DateTime createdAt, {
  String taskId = 'task-1',
  String status = 'active',
  int completedReps = 0,
  DateTime? closedAt,
}) {
  return {
    'groupId': 'group-1',
    'failedUserId': 'alice',
    'failedTaskSessionId': taskId,
    'memberCountAtFailure': 5,
    'repsPerMember': 10,
    'totalReps': 50,
    'completedReps': completedReps,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
    'lockExpiresAt': Timestamp.fromDate(
      createdAt.add(const Duration(minutes: 30)),
    ),
    'closedAt': closedAt == null ? null : Timestamp.fromDate(closedAt),
    'lastContributionAt': null,
    'lastContributionEventId': null,
    'schemaVersion': 1,
  };
}
