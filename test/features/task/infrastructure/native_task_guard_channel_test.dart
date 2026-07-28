import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/task/domain/native_task_guard.dart';
import 'package:michizure/features/task/domain/task_session.dart';
import 'package:michizure/features/task/infrastructure/native_task_guard_channel.dart';

import '../support/fake_task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('test/task_guard_methods/v1');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'uses versioned start, state, acknowledgement, and stop methods',
    () async {
      final calls = <MethodCall>[];
      _handle(methodChannel, (call) {
        calls.add(call);
        return switch (call.method) {
          'startTaskGuard' => {
            'contractVersion': 1,
            'taskSessionId': 'task-1',
            'isRunning': true,
          },
          'getTaskGuardState' => {
            'contractVersion': 1,
            'taskSessionId': 'task-1',
            'isRunning': true,
            'hasPendingEvent': false,
          },
          'ackTaskEvent' => {'contractVersion': 1, 'acknowledged': true},
          'stopTaskGuard' => {
            'contractVersion': 1,
            'taskSessionId': 'task-1',
            'isRunning': false,
            'changed': true,
          },
          _ => throw MissingPluginException(),
        };
      });
      final guard = MethodChannelNativeTaskGuard(methodChannel: methodChannel);
      final task = runningTaskFixture();

      expect((await guard.start(task)).isRunning, isTrue);
      expect((await guard.getState()).taskSessionId, task.id);
      expect(await guard.acknowledge('event-1'), isTrue);
      await guard.stop(task.id);

      expect(calls.map((call) => call.method), [
        'startTaskGuard',
        'getTaskGuardState',
        'ackTaskEvent',
        'stopTaskGuard',
      ]);
      final start = calls.first.arguments as Map<Object?, Object?>;
      expect(start['contractVersion'], 1);
      expect(start['taskSessionId'], task.id);
      expect(start['startedAtEpochMs'], task.startedAt.millisecondsSinceEpoch);
      expect(
        start['expectedEndAtEpochMs'],
        task.expectedEndAt.millisecondsSinceEpoch,
      );
    },
  );

  test('maps native error codes without exposing platform messages', () async {
    _handle(
      methodChannel,
      (_) => throw PlatformException(
        code: 'usageAccessMissing',
        message: 'raw native detail',
      ),
    );
    final guard = MethodChannelNativeTaskGuard(methodChannel: methodChannel);

    await expectLater(
      guard.start(runningTaskFixture()),
      throwsA(
        isA<NativeTaskGuardFailure>().having(
          (failure) => failure.kind,
          'kind',
          NativeTaskGuardFailureKind.usageAccessMissing,
        ),
      ),
    );
  });

  test('parses only the minimal versioned event contract', () {
    final event = nativeTaskEventFromWire({
      'contractVersion': 1,
      'eventId': 'event-1',
      'taskSessionId': 'task-1',
      'eventType': 'taskFailed',
      'occurredAtEpochMs': 1000,
      'reason': 'foreign_app_foreground',
    });

    expect(event.type, NativeTaskEventType.taskFailed);
    expect(event.failureReason, TaskFailureReason.foreignAppForeground);
    expect(
      event.occurredAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

    expect(
      () => nativeTaskEventFromWire({
        'contractVersion': 1,
        'eventId': 'event-2',
        'taskSessionId': 'task-1',
        'eventType': 'taskFailed',
        'occurredAtEpochMs': 1000,
        'reason': 'foreign_app_foreground',
        'packageName': 'must.not.cross.the.bridge',
      }),
      throwsA(
        isA<NativeTaskGuardFailure>().having(
          (failure) => failure.kind,
          'kind',
          NativeTaskGuardFailureKind.channelContractMismatch,
        ),
      ),
    );
  });

  test('rejects malformed and mismatched event payloads', () {
    expect(
      () =>
          nativeTaskEventFromWire({'contractVersion': 2, 'eventId': 'event-1'}),
      throwsA(isA<NativeTaskGuardFailure>()),
    );
    expect(
      () => nativeTaskEventFromWire({
        'contractVersion': 1,
        'eventId': 'event-1',
        'taskSessionId': 'task-1',
        'eventType': 'deadlineReached',
        'occurredAtEpochMs': 1000,
        'reason': 'foreign_app_foreground',
      }),
      throwsA(
        isA<NativeTaskGuardFailure>().having(
          (failure) => failure.kind,
          'kind',
          NativeTaskGuardFailureKind.invalidData,
        ),
      ),
    );
  });
}

void _handle(
  MethodChannel channel,
  FutureOr<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));
}
