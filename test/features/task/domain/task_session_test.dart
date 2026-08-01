import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/task/domain/task_session.dart';

void main() {
  group('TaskContentValidator', () {
    test('accepts normalized Unicode task content', () {
      for (final content in ['勉強する', '論文を書く', 'Read paper', '数学の課題']) {
        expect(TaskContentValidator.isValid(content), isTrue, reason: content);
      }
    });

    test('normalizes surrounding whitespace', () {
      expect(TaskContentValidator.normalize('  勉強する  '), '勉強する');
    });

    test('rejects blank, control characters, and over 100 scalars', () {
      for (final content in ['', '  ', '\n', '勉強\nする', '学' * 101]) {
        expect(TaskContentValidator.isValid(content), isFalse, reason: content);
      }
    });
  });

  test('duration is limited to 60 through 10,800 seconds', () {
    expect(TaskDurationValidator.isValidSeconds(59), isFalse);
    expect(TaskDurationValidator.isValidSeconds(60), isTrue);
    expect(TaskDurationValidator.isValidSeconds(10800), isTrue);
    expect(TaskDurationValidator.isValidSeconds(10801), isFalse);
  });

  group('remaining time', () {
    final startedAt = DateTime.utc(2026, 1, 1, 10);
    final task = _runningTask(startedAt);

    test('is derived from expectedEndAt at start and midway', () {
      expect(task.remainingAt(startedAt), const Duration(minutes: 30));
      expect(
        task.remainingAt(startedAt.add(const Duration(minutes: 15))),
        const Duration(minutes: 15),
      );
    });

    test('preserves the final instant and clamps after deadline to zero', () {
      expect(
        task.remainingAt(
          task.expectedEndAt.subtract(const Duration(milliseconds: 1)),
        ),
        const Duration(milliseconds: 1),
      );
      expect(task.remainingAt(task.expectedEndAt), Duration.zero);
      expect(
        task.remainingAt(task.expectedEndAt.add(const Duration(minutes: 10))),
        Duration.zero,
      );
    });

    test('terminal tasks always have zero remaining', () {
      final succeeded = TaskSession(
        id: task.id,
        ownerUid: task.ownerUid,
        groupId: task.groupId,
        content: task.content,
        durationSeconds: task.durationSeconds,
        startedAt: task.startedAt,
        serverRecordedAt: task.serverRecordedAt,
        expectedEndAt: task.expectedEndAt,
        status: TaskSessionStatus.succeeded,
        endedAt: task.expectedEndAt,
        failureReason: null,
        failureEventId: null,
        groupMemberCountAtFailure: null,
        debtId: null,
        lockDurationSeconds: task.lockDurationSeconds,
        guardConfigVersion: task.guardConfigVersion,
      );

      expect(
        succeeded.remainingAt(startedAt.add(const Duration(minutes: 1))),
        Duration.zero,
      );
    });
  });
}

TaskSession _runningTask(DateTime startedAt) {
  return TaskSession(
    id: 'task-1',
    ownerUid: 'alice',
    groupId: 'group-1',
    content: '勉強する',
    durationSeconds: 1800,
    startedAt: startedAt,
    serverRecordedAt: startedAt,
    expectedEndAt: startedAt.add(const Duration(minutes: 30)),
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
