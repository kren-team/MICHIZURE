import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/task/application/handle_native_task_event.dart';
import 'package:michizure/features/task/domain/native_task_guard.dart';
import 'package:michizure/features/task/domain/task_failure.dart';
import 'package:michizure/features/task/domain/task_session.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';

import '../support/fake_native_task_guard.dart';
import '../support/fake_task_repository.dart';
import '../../enforcement/support/fake_app_lock_repository.dart';

void main() {
  late FakeTaskRepository tasks;
  late FakeNativeTaskGuard guard;
  late ProviderContainer container;
  late FakeAppLockRepository appLock;

  setUp(() {
    tasks = FakeTaskRepository();
    guard = FakeNativeTaskGuard();
    appLock = FakeAppLockRepository();
    container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(tasks),
        nativeTaskGuardProvider.overrideWithValue(guard),
        appLockRepositoryProvider.overrideWithValue(appLock),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(guard.close);
  });

  test(
    'foreign failure creates one Debt then acknowledges native outbox',
    () async {
      final controller = container.read(taskGuardControllerProvider.notifier);
      final task = runningTaskFixture();
      await controller.ensureStarted(task);

      guard.emit(_failureEvent(task));
      await _flush();

      expect(tasks.failCalls, 1);
      expect(appLock.applyCalls, 1);
      expect(tasks.lastFailureEventId, 'native-event-1');
      expect(guard.acknowledgedEventIds, ['native-event-1']);
      expect(
        container.read(taskGuardControllerProvider).phase,
        TaskGuardPhase.terminal,
      );

      guard.emit(_failureEvent(task));
      await _flush();
      expect(tasks.failCalls, 1);
      expect(guard.acknowledgeCalls, 1);
      expect(appLock.applyCalls, 1);
    },
  );

  test(
    'replayed event restores its Task before processing after app restart',
    () async {
      container.read(taskGuardControllerProvider);

      guard.emit(_failureEvent(runningTaskFixture()));
      await _flush();

      expect(tasks.failCalls, 1);
      expect(guard.acknowledgedEventIds, ['native-event-1']);
    },
  );

  test(
    'Firestore-confirmed replay applies lock before native acknowledgement',
    () async {
      final terminal = _failedForNativeEvent();
      tasks.taskStream = Stream.value(terminal);
      container.read(taskGuardControllerProvider);

      guard.emit(_failureEvent(terminal));
      await _flush();

      expect(tasks.failCalls, 1);
      expect(appLock.applyCalls, 1);
      expect(guard.acknowledgedEventIds, ['native-event-1']);
    },
  );

  test(
    'offline failure stays pending and retry uses the same event ID',
    () async {
      tasks.failError = const TaskFailure(TaskFailureKind.offline);
      final controller = container.read(taskGuardControllerProvider.notifier);
      final task = runningTaskFixture();
      await controller.ensureStarted(task);

      guard.emit(_failureEvent(task));
      await _flush();

      expect(tasks.failCalls, 1);
      expect(guard.acknowledgeCalls, 0);
      expect(appLock.applyCalls, 0);
      expect(
        container.read(taskGuardControllerProvider).phase,
        TaskGuardPhase.retryNeeded,
      );

      tasks.failError = null;
      await controller.retry();

      expect(tasks.failCalls, 2);
      expect(appLock.applyCalls, 1);
      expect(tasks.lastFailureEventId, 'native-event-1');
      expect(guard.acknowledgedEventIds, ['native-event-1']);
    },
  );

  test(
    'deadline event succeeds and duplicate in-flight delivery is suppressed',
    () async {
      final completer = Completer<void>();
      tasks.succeedCompleter = completer;
      final controller = container.read(taskGuardControllerProvider.notifier);
      final task = runningTaskFixture();
      await controller.ensureStarted(task);
      final event = _deadlineEvent(task);

      guard.emit(event);
      guard.emit(event);
      await _flush();

      expect(tasks.succeedCalls, 1);
      expect(appLock.applyCalls, 0);
      completer.complete();
      await _flush();
      expect(guard.acknowledgeCalls, 1);
    },
  );

  test(
    'lock capability failure keeps the native event pending for retry',
    () async {
      appLock.error = const EnforcementFailure(
        EnforcementFailureKind.notDeviceOwner,
      );
      final controller = container.read(taskGuardControllerProvider.notifier);
      final task = runningTaskFixture();
      await controller.ensureStarted(task);

      guard.emit(_failureEvent(task));
      await _flush();

      expect(tasks.failCalls, 1);
      expect(appLock.applyCalls, 1);
      expect(guard.acknowledgeCalls, 0);

      appLock.error = null;
      await controller.retry();

      expect(tasks.failCalls, 2);
      expect(appLock.applyCalls, 2);
      expect(guard.acknowledgeCalls, 1);
    },
  );

  test(
    'an event for an already terminal Task is acknowledged without a rewrite',
    () async {
      final controller = container.read(taskGuardControllerProvider.notifier);
      final task = failedTaskFixture();
      guard.activeTaskId = task.id;
      await controller.ensureStarted(task);

      guard.emit(_failureEvent(task));
      await _flush();

      expect(tasks.failCalls, 0);
      expect(tasks.succeedCalls, 0);
      expect(guard.acknowledgeCalls, 1);
    },
  );

  test('typed native stream failure becomes retryable safe state', () async {
    final controller = container.read(taskGuardControllerProvider.notifier);
    await controller.ensureStarted(runningTaskFixture());

    guard.emitError(
      const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.usageAccessMissing,
      ),
    );
    await _flush();

    final state = container.read(taskGuardControllerProvider);
    expect(state.phase, TaskGuardPhase.retryNeeded);
    expect(
      state.failure,
      isA<NativeTaskGuardFailure>().having(
        (failure) => failure.kind,
        'kind',
        NativeTaskGuardFailureKind.usageAccessMissing,
      ),
    );
  });
}

NativeTaskEvent _failureEvent(TaskSession task) {
  return NativeTaskEvent(
    eventId: 'native-event-1',
    taskSessionId: task.id,
    type: NativeTaskEventType.taskFailed,
    occurredAt: task.startedAt.add(const Duration(seconds: 10)),
    failureReason: TaskFailureReason.foreignAppForeground,
  );
}

NativeTaskEvent _deadlineEvent(TaskSession task) {
  return NativeTaskEvent(
    eventId: 'native-deadline-1',
    taskSessionId: task.id,
    type: NativeTaskEventType.deadlineReached,
    occurredAt: task.expectedEndAt,
    failureReason: null,
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

TaskSession _failedForNativeEvent() {
  final failed = failedTaskFixture();
  return TaskSession(
    id: failed.id,
    ownerUid: failed.ownerUid,
    groupId: failed.groupId,
    content: failed.content,
    durationSeconds: failed.durationSeconds,
    startedAt: failed.startedAt,
    serverRecordedAt: failed.serverRecordedAt,
    expectedEndAt: failed.expectedEndAt,
    status: failed.status,
    endedAt: failed.endedAt,
    failureReason: TaskFailureReason.foreignAppForeground,
    failureEventId: 'native-event-1',
    groupMemberCountAtFailure: failed.groupMemberCountAtFailure,
    debtId: failed.debtId,
    lockDurationSeconds: failed.lockDurationSeconds,
    guardConfigVersion: failed.guardConfigVersion,
  );
}
