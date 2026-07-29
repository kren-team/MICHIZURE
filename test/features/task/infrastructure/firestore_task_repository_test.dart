import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/infrastructure/firestore_debt_repository.dart';
import 'package:michizure/features/task/domain/task_failure.dart';
import 'package:michizure/features/task/domain/task_session.dart';
import 'package:michizure/features/task/infrastructure/firestore_task_repository.dart';

void main() {
  final startedAt = DateTime.utc(2026, 1, 1, 10);

  test('converts valid running and failed task documents', () {
    final running = taskSessionFromFirestore('task-1', _taskData(startedAt));
    final failed = taskSessionFromFirestore(
      'task-1',
      _taskData(startedAt, failed: true),
    );

    expect(running.status, TaskSessionStatus.running);
    expect(running.expectedEndAt, startedAt.add(const Duration(minutes: 30)));
    expect(failed.status, TaskSessionStatus.failed);
    expect(failed.failureReason, TaskFailureReason.userAborted);
    expect(failed.debtId, 'task-1');
  });

  test('rejects unknown fields and inconsistent expectedEndAt', () {
    expect(
      () => taskSessionFromFirestore('task-1', {
        ..._taskData(startedAt),
        'unexpected': true,
      }),
      throwsA(isA<TaskFailure>()),
    );
    expect(
      () => taskSessionFromFirestore('task-1', {
        ..._taskData(startedAt),
        'expectedEndAt': Timestamp.fromDate(
          startedAt.add(const Duration(minutes: 29)),
        ),
      }),
      throwsA(isA<TaskFailure>()),
    );
  });

  test('converts a valid initial debt and derives remaining reps', () {
    final createdAt = Timestamp.fromDate(startedAt);
    final debt = debtFromFirestore('task-1', {
      'groupId': 'group-1',
      'failedUserId': 'alice',
      'failedTaskSessionId': 'task-1',
      'memberCountAtFailure': 5,
      'repsPerMember': 10,
      'totalReps': 50,
      'completedReps': 0,
      'status': 'active',
      'createdAt': createdAt,
      'lockExpiresAt': Timestamp.fromDate(
        startedAt.add(const Duration(minutes: 30)),
      ),
      'closedAt': null,
      'lastContributionAt': null,
      'lastContributionEventId': null,
      'schemaVersion': 1,
    });

    expect(debt.status, DebtStatus.active);
    expect(debt.remainingReps, 50);
  });
}

Map<String, Object?> _taskData(DateTime startedAt, {bool failed = false}) {
  return {
    'ownerUid': 'alice',
    'groupId': 'group-1',
    'content': '勉強する',
    'durationSec': 1800,
    'startedAt': Timestamp.fromDate(startedAt),
    'serverRecordedAt': Timestamp.fromDate(startedAt),
    'expectedEndAt': Timestamp.fromDate(
      startedAt.add(const Duration(minutes: 30)),
    ),
    'status': failed ? 'failed' : 'running',
    'endedAt': failed
        ? Timestamp.fromDate(startedAt.add(const Duration(minutes: 5)))
        : null,
    'failureReason': failed ? 'user_aborted' : null,
    'failureEventId': failed ? 'manual-event-1' : null,
    'groupMemberCountAtFailure': failed ? 5 : null,
    'debtId': failed ? 'task-1' : null,
    'lockDurationSec': 1800,
    'guardConfigVersion': 1,
    'schemaVersion': 1,
  };
}
