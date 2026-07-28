import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/enforcement/domain/device_capabilities.dart';
import 'package:michizure/features/task/application/start_task.dart';
import 'package:michizure/features/task/domain/task_failure.dart';

import '../../enforcement/support/fake_device_control_repository.dart';
import '../support/fake_task_repository.dart';

void main() {
  late FakeTaskRepository tasks;
  late FakeDeviceControlRepository device;
  late StartTask startTask;

  setUp(() {
    tasks = FakeTaskRepository();
    device = FakeDeviceControlRepository()
      ..selectedPackageNames = {'social.app'};
    startTask = StartTask(tasks, device);
  });

  test('preflights the device and starts a normalized Task', () async {
    final task = await startTask(
      ownerUid: 'alice',
      groupId: 'group-1',
      content: '  論文を書く  ',
      durationSeconds: 1800,
    );

    expect(task.id, 'task-1');
    expect(device.capabilityCalls, 1);
    expect(device.readSelectionCalls, 1);
    expect(tasks.startCalls, 1);
    expect(tasks.lastStartRequest?.content, '論文を書く');
  });

  test('rejects an unprepared device without writing a Task', () async {
    device.capabilities = const DeviceCapabilities(
      isDeviceOwner: false,
      hasUsageAccess: true,
      hasNotificationPermission: true,
      packageVisibility: PackageVisibility.broad,
      isUserUnlocked: true,
      supportsHardEnforcement: true,
      sdkInt: 36,
    );

    await expectLater(
      startTask(
        ownerUid: 'alice',
        groupId: 'group-1',
        content: '勉強する',
        durationSeconds: 60,
      ),
      throwsA(
        isA<TaskFailure>().having(
          (failure) => failure.kind,
          'kind',
          TaskFailureKind.deviceNotReady,
        ),
      ),
    );
    expect(tasks.startCalls, 0);
  });

  test(
    'rejects an empty lock target selection without writing a Task',
    () async {
      device.selectedPackageNames = {};

      await expectLater(
        startTask(
          ownerUid: 'alice',
          groupId: 'group-1',
          content: '勉強する',
          durationSeconds: 60,
        ),
        throwsA(
          isA<TaskFailure>().having(
            (failure) => failure.kind,
            'kind',
            TaskFailureKind.noLockTargets,
          ),
        ),
      );
      expect(tasks.startCalls, 0);
    },
  );
}
