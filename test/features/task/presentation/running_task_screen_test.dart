import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/core/time/clock.dart';
import 'package:michizure/features/task/domain/task_failure.dart';
import 'package:michizure/features/task/domain/task_session.dart';
import 'package:michizure/features/task/presentation/running_task_screen.dart';

import '../support/fake_task_repository.dart';

void main() {
  testWidgets('restores a running Task from expectedEndAt midway', (
    tester,
  ) async {
    final task = runningTaskFixture();
    await _pumpRunning(
      tester,
      task: task,
      clock: _FakeClock(task.startedAt.add(const Duration(minutes: 15))),
    );

    expect(find.text('勉強する'), findsOneWidget);
    expect(find.text('00:15:00'), findsOneWidget);
  });

  testWidgets('converges an overdue recovered Task to success', (tester) async {
    final tasks = FakeTaskRepository();
    final task = runningTaskFixture();
    await _pumpRunning(
      tester,
      tasks: tasks,
      task: task,
      clock: _FakeClock(task.expectedEndAt),
    );
    await tester.pump();
    await tester.pump();

    expect(tasks.succeedCalls, 1);
    expect(find.byKey(const Key('task-success-title')), findsOneWidget);
  });

  testWidgets('shows a safe retry when success transaction fails', (
    tester,
  ) async {
    final tasks = FakeTaskRepository()
      ..succeedError = const TaskFailure(TaskFailureKind.offline);
    final task = runningTaskFixture();
    await _pumpRunning(
      tester,
      tasks: tasks,
      task: task,
      clock: _FakeClock(task.expectedEndAt),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('running-task-error')), findsOneWidget);
    expect(find.byKey(const Key('task-success-retry-button')), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });

  testWidgets('manual abort creates a failed Task result', (tester) async {
    final tasks = FakeTaskRepository();
    final task = runningTaskFixture();
    await _pumpRunning(
      tester,
      tasks: tasks,
      task: task,
      clock: _FakeClock(task.startedAt.add(const Duration(minutes: 1))),
    );

    await tester.tap(find.byKey(const Key('task-abort-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-abort-confirm-button')));
    await tester.pump();
    await tester.pump();

    expect(tasks.failCalls, 1);
    expect(find.byKey(const Key('task-failed-title')), findsOneWidget);
    expect(find.text('発生した負債: 50回'), findsOneWidget);
  });
}

Future<void> _pumpRunning(
  WidgetTester tester, {
  FakeTaskRepository? tasks,
  required TaskSession task,
  required Clock clock,
}) async {
  final repository = tasks ?? FakeTaskRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(repository),
        activeTaskSessionProvider.overrideWithValue(AsyncData(task)),
        clockProvider.overrideWithValue(clock),
      ],
      child: const MaterialApp(home: RunningTaskScreen()),
    ),
  );
  await tester.pump();
}

final class _FakeClock implements Clock {
  const _FakeClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
