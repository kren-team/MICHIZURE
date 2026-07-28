import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/task/application/task_command_controller.dart';
import 'package:michizure/features/task/application/task_event_id_generator.dart';
import 'package:michizure/features/task/domain/task_failure.dart';

import '../../enforcement/support/fake_device_control_repository.dart';
import '../support/fake_task_repository.dart';

void main() {
  late FakeTaskRepository tasks;
  late FakeDeviceControlRepository device;
  late ProviderContainer container;

  setUp(() {
    tasks = FakeTaskRepository();
    device = FakeDeviceControlRepository()
      ..selectedPackageNames = {'social.app'};
    container = ProviderContainer(
      overrides: [
        taskRepositoryProvider.overrideWithValue(tasks),
        deviceControlRepositoryProvider.overrideWithValue(device),
        taskEventIdGeneratorProvider.overrideWithValue(
          const _FixedEventIdGenerator(),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('start is single-flight', () async {
    final completer = Completer<void>();
    tasks.startCompleter = completer;
    final controller = container.read(taskCommandControllerProvider.notifier);

    final first = controller.start(
      ownerUid: 'alice',
      groupId: 'group-1',
      content: '勉強する',
      durationSeconds: 1800,
    );
    final second = controller.start(
      ownerUid: 'alice',
      groupId: 'group-1',
      content: '勉強する',
      durationSeconds: 1800,
    );
    await Future<void>.delayed(Duration.zero);

    expect(tasks.startCalls, 1);
    expect(await second, isFalse);
    completer.complete();
    expect(await first, isTrue);
  });

  test('surfaces a typed repository failure', () async {
    tasks.startError = const TaskFailure(TaskFailureKind.offline);

    final succeeded = await container
        .read(taskCommandControllerProvider.notifier)
        .start(
          ownerUid: 'alice',
          groupId: 'group-1',
          content: '勉強する',
          durationSeconds: 1800,
        );

    expect(succeeded, isFalse);
    expect(
      container.read(taskCommandControllerProvider).error,
      isA<TaskFailure>().having(
        (failure) => failure.kind,
        'kind',
        TaskFailureKind.offline,
      ),
    );
  });

  test('success and manual abort use repository terminal operations', () async {
    final controller = container.read(taskCommandControllerProvider.notifier);

    expect(
      await controller.succeed(ownerUid: 'alice', taskId: 'task-1'),
      isTrue,
    );
    expect(tasks.succeedCalls, 1);

    expect(await controller.abort(ownerUid: 'alice', taskId: 'task-1'), isTrue);
    expect(tasks.failCalls, 1);
    expect(tasks.lastFailureEventId, 'manual_task-1_fixed');
    expect(
      container.read(taskCommandControllerProvider).value?.debt?.totalReps,
      50,
    );
  });
}

final class _FixedEventIdGenerator implements TaskEventIdGenerator {
  const _FixedEventIdGenerator();

  @override
  String generateManualAbortId(String taskId) => 'manual_${taskId}_fixed';
}
