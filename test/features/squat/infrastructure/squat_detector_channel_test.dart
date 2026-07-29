import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/squat/domain/squat_detector.dart';
import 'package:michizure/features/squat/infrastructure/squat_detector_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/squat_control/v1');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses versioned permission start and stop commands', () async {
    final calls = <MethodCall>[];
    _handle(channel, (call) {
      calls.add(call);
      return switch (call.method) {
        'getCameraPermissionState' ||
        'requestCameraPermission' => {'contractVersion': 1, 'state': 'granted'},
        'startSession' => {
          'contractVersion': 1,
          'started': true,
          'squatSessionId': 'session-12345678',
        },
        'stopSession' => {'contractVersion': 1, 'stopped': true},
        _ => {'contractVersion': 1},
      };
    });
    final detector = MethodChannelSquatDetector(methodChannel: channel);

    expect(
      await detector.getCameraPermissionState(),
      CameraPermissionState.granted,
    );
    await detector.start(
      const SquatDetectorSession(
        squatSessionId: 'session-12345678',
        debtId: 'debt-1',
      ),
    );
    await detector.stop(squatSessionId: 'session-12345678');

    expect(calls.map((call) => call.method), [
      'getCameraPermissionState',
      'startSession',
      'stopSession',
    ]);
    expect((calls[1].arguments as Map)['contractVersion'], 1);
    expect((calls[1].arguments as Map)['debtId'], 'debt-1');
  });

  test('maps camera permission and native errors to typed failures', () async {
    _handle(
      channel,
      (_) => throw PlatformException(
        code: 'cameraPermissionPermanentlyDenied',
        message: 'raw platform detail',
      ),
    );
    final detector = MethodChannelSquatDetector(methodChannel: channel);

    await expectLater(
      detector.requestCameraPermission(),
      throwsA(
        isA<SquatDetectorFailure>().having(
          (value) => value.reason,
          'reason',
          SquatDetectorFailureReason.permissionPermanentlyDenied,
        ),
      ),
    );
  });

  test(
    'parses a minimal rep event and rejects private or malformed fields',
    () {
      final detector = MethodChannelSquatDetector(methodChannel: channel);
      final event = detector.parseEvent({
        'contractVersion': 1,
        'type': 'repCompleted',
        'eventId': 'session-12345678_1',
        'occurredAtEpochMs': 1_000,
        'squatSessionId': 'session-12345678',
        'sequence': 1,
        'detectorType': 'mlkit',
        'detectorVersion': 'squat-v1',
        'frameObservedElapsedMs': 500,
        'uiEmittedElapsedMs': 550,
        'analysisLatencyMs': 50,
      });

      expect(event, isA<SquatRepCompleted>());
      expect((event as SquatRepCompleted).sequence, 1);
      expect(event.analysisLatencyMs, 50);

      for (final forbidden in ['landmarks', 'bitmap', 'frame', 'image']) {
        expect(
          () => detector.parseEvent({
            'contractVersion': 1,
            'type': 'repCompleted',
            'eventId': 'session-12345678_1',
            'occurredAtEpochMs': 1_000,
            'squatSessionId': 'session-12345678',
            'sequence': 1,
            'detectorType': 'mlkit',
            'detectorVersion': 'squat-v1',
            'frameObservedElapsedMs': 500,
            'uiEmittedElapsedMs': 550,
            'analysisLatencyMs': 50,
            forbidden: <Object>[],
          }),
          throwsA(isA<SquatDetectorFailure>()),
        );
      }
      expect(
        () => detector.parseEvent({'contractVersion': 2, 'eventId': 'bad'}),
        throwsA(isA<SquatDetectorFailure>()),
      );
      for (final invalidIdentity in [
        {'eventId': 'session-12345678_2'},
        {'detectorType': 'synthetic'},
        {'squatSessionId': 'short'},
      ]) {
        expect(
          () => detector.parseEvent({
            'contractVersion': 1,
            'type': 'repCompleted',
            'eventId': 'session-12345678_1',
            'occurredAtEpochMs': 1_000,
            'squatSessionId': 'session-12345678',
            'sequence': 1,
            'detectorType': 'mlkit',
            'detectorVersion': 'squat-v1',
            'frameObservedElapsedMs': 500,
            'uiEmittedElapsedMs': 550,
            'analysisLatencyMs': 50,
            ...invalidIdentity,
          }),
          throwsA(isA<SquatDetectorFailure>()),
        );
      }
    },
  );
}

void _handle(
  MethodChannel channel,
  FutureOr<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));
}
