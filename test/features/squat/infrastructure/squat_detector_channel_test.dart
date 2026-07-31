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

  test('parses MediaPipe readiness and delegate', () {
    final detector = MethodChannelSquatDetector(methodChannel: channel);
    final event = detector.parseEvent({
      'contractVersion': 1,
      'type': 'detectorReady',
      'eventId': 'session-12345678_ready_1',
      'occurredAtEpochMs': 1_000,
      'squatSessionId': 'session-12345678',
      'detectorType': 'mediapipe',
      'detectorVersion': 'mediapipe-lite-v1',
      'delegate': 'gpu',
    });

    expect(event, isA<SquatDetectorReady>());
    expect((event as SquatDetectorReady).delegate, SquatInferenceDelegate.gpu);
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
        'detectorType': 'mediapipe',
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
            'detectorType': 'mediapipe',
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
            'detectorType': 'mediapipe',
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

  test('parses lower-body diagnostics and rejects coordinate payloads', () {
    final detector = MethodChannelSquatDetector(methodChannel: channel);
    final event = detector.parseEvent({
      'contractVersion': 1,
      'type': 'diagnostics',
      'eventId': 'session-12345678_diagnostics_1000',
      'occurredAtEpochMs': 1_000,
      'squatSessionId': 'session-12345678',
      'poseDetected': true,
      'trackingStatus': 'valid',
      'pipelineStatus': 'valid',
      'selectedSide': 'left',
      'leftHipConfidence': 0.90,
      'leftKneeConfidence': 0.91,
      'leftAnkleConfidence': 0.88,
      'rightHipConfidence': null,
      'rightKneeConfidence': null,
      'rightAnkleConfidence': null,
      'rawKneeAngle': 121.5,
      'kneeAngle': 120.0,
      'normalizedHipDrop': 0.13,
      'kneeAngularVelocity': -21.0,
      'hipVerticalVelocity': 0.12,
      'state': 'descending',
      'previousState': 'standing',
      'lastTransitionReason': 'descentConfirmed',
      'latestRejectReason': null,
      'lastResetReason': null,
      'frameDtMs': 100,
      'validPoseAgeMs': 0,
      'effectiveValidPoseFps': 8.0,
      'calibrationSampleCount': 8,
      'calibrationStatus': 'complete',
      'bottomReached': false,
      'standingConfirmationDurationMs': 0,
      'bottomConfirmationDurationMs': 0,
      'returnStandingDurationMs': 0,
      'currentRepDurationMs': 250,
      'calibratedStandingKneeAngle': 168.0,
      'standingThresholdDeg': 150.0,
      'descendingThresholdDeg': 148.0,
      'bottomThresholdDeg': 140.0,
      'returnStandingThresholdDeg': 146.0,
      'minimumAttemptKneeAngle': 132.0,
      'maximumAttemptHipDrop': 0.11,
      'kneeBendDelta': 36.0,
      'downwardMovementObserved': true,
      'upwardMovementObserved': false,
      'bottomEvidenceScore': 5,
      'bottomEvidencePath': 'KNEE_ONLY',
      'attemptStartTimestampMs': 750,
      'lastValidPoseTimestampMs': 1_000,
      'baselineHipY': 0.25,
      'legScale': 0.50,
      'baselineJitter': 0.01,
      'calibrationSelectedSide': 'left',
      'analysisLatencyMs': 80,
      'acceptedReps': 1,
      'rejectedAttempts': 0,
      'delegate': 'cpu',
      'sampleCount': 20,
      'analyzerFrames': 40,
      'inferenceSubmitted': 22,
      'resultCallbacks': 20,
      'resultsWithPose': 17,
      'resultsWithoutPose': 3,
      'errorCallbacks': 0,
      'lastCallbackAgeMs': 25,
      'activeDelegate': 'cpu',
      'lastError': null,
      'analyzerInputFps': 30.0,
      'inferenceSubmittedFps': 10.0,
      'resultCallbackFps': 9.5,
      'validPoseFps': 8.0,
      'actualAnalysisFps': 10.0,
      'requestedAnalysisWidth': 320,
      'requestedAnalysisHeight': 240,
      'actualAnalysisWidth': 320,
      'actualAnalysisHeight': 240,
      'droppedBeforePreprocessing': 12,
      'rejectedAsBusy': 2,
      'convertedBitmapCount': 7,
      'rotationBitmapCount': 7,
      'resultCount': 20,
      'noPoseCount': 3,
      'preprocessingP50Ms': 4,
      'preprocessingP95Ms': 8,
      'inferenceP50Ms': 45,
      'inferenceP95Ms': 80,
      'nativePipelineP50Ms': 55,
      'nativePipelineP95Ms': 95,
      'diagnosticEventFps': 5.0,
    });

    expect(event, isA<SquatDetectorDiagnostics>());
    final diagnostics = event as SquatDetectorDiagnostics;
    expect(diagnostics.selectedSide, SquatPoseSide.left);
    expect(diagnostics.leftKneeConfidence, 0.91);
    expect(diagnostics.trackingStatus, SquatPoseTrackingStatus.valid);
    expect(diagnostics.kneeAngle, 120);
    expect(diagnostics.rawKneeAngle, 121.5);
    expect(diagnostics.previousState, SquatDetectorState.standing);
    expect(diagnostics.lastTransitionReason, 'descentConfirmed');
    expect(diagnostics.calibrationSampleCount, 8);
    expect(diagnostics.validPoseFps, 8);
    expect(diagnostics.calibratedStandingKneeAngle, 168);
    expect(diagnostics.standingThresholdDeg, 150);
    expect(diagnostics.descendingThresholdDeg, 148);
    expect(diagnostics.bottomThresholdDeg, 140);
    expect(diagnostics.returnStandingThresholdDeg, 146);
    expect(diagnostics.minimumAttemptKneeAngle, 132);
    expect(diagnostics.maximumAttemptHipDrop, 0.11);
    expect(diagnostics.kneeBendDelta, 36);
    expect(diagnostics.downwardMovementObserved, isTrue);
    expect(diagnostics.upwardMovementObserved, isFalse);
    expect(diagnostics.bottomEvidenceScore, 5);
    expect(diagnostics.bottomEvidencePath, SquatBottomEvidencePath.kneeOnly);
    expect(diagnostics.attemptStartTimestampMs, 750);
    expect(diagnostics.lastValidPoseTimestampMs, 1000);
    expect(diagnostics.calibrationSelectedSide, SquatPoseSide.left);
    expect(diagnostics.requestedAnalysisWidth, 320);
    expect(diagnostics.requestedAnalysisHeight, 240);
    expect(diagnostics.actualAnalysisWidth, 320);
    expect(diagnostics.actualAnalysisHeight, 240);

    expect(
      () => detector.parseEvent({
        'contractVersion': 1,
        'type': 'diagnostics',
        'eventId': 'session-12345678_diagnostics_1000',
        'occurredAtEpochMs': 1_000,
        'squatSessionId': 'session-12345678',
        'poseDetected': true,
        'trackingStatus': 'valid',
        'pipelineStatus': 'valid',
        'selectedSide': 'left',
        'leftHipConfidence': 0.90,
        'leftKneeConfidence': 0.91,
        'leftAnkleConfidence': 0.88,
        'rightHipConfidence': null,
        'rightKneeConfidence': null,
        'rightAnkleConfidence': null,
        'rawKneeAngle': 121.5,
        'kneeAngle': 120.0,
        'normalizedHipDrop': 0.13,
        'kneeAngularVelocity': -21.0,
        'hipVerticalVelocity': 0.12,
        'state': 'descending',
        'previousState': 'standing',
        'lastTransitionReason': 'descentConfirmed',
        'latestRejectReason': null,
        'lastResetReason': null,
        'frameDtMs': 100,
        'validPoseAgeMs': 0,
        'effectiveValidPoseFps': 8.0,
        'calibrationSampleCount': 8,
        'calibrationStatus': 'complete',
        'bottomReached': false,
        'standingConfirmationDurationMs': 0,
        'bottomConfirmationDurationMs': 0,
        'returnStandingDurationMs': 0,
        'currentRepDurationMs': 250,
        'calibratedStandingKneeAngle': 168.0,
        'standingThresholdDeg': 150.0,
        'descendingThresholdDeg': 148.0,
        'bottomThresholdDeg': 140.0,
        'returnStandingThresholdDeg': 146.0,
        'minimumAttemptKneeAngle': 132.0,
        'maximumAttemptHipDrop': 0.11,
        'kneeBendDelta': 36.0,
        'downwardMovementObserved': true,
        'upwardMovementObserved': false,
        'bottomEvidenceScore': 5,
        'bottomEvidencePath': 'KNEE_ONLY',
        'attemptStartTimestampMs': 750,
        'lastValidPoseTimestampMs': 1_000,
        'baselineHipY': 0.25,
        'legScale': 0.50,
        'baselineJitter': 0.01,
        'calibrationSelectedSide': 'left',
        'analysisLatencyMs': 80,
        'acceptedReps': 1,
        'rejectedAttempts': 0,
        'delegate': 'cpu',
        'sampleCount': 20,
        'analyzerFrames': 40,
        'inferenceSubmitted': 22,
        'resultCallbacks': 20,
        'resultsWithPose': 17,
        'resultsWithoutPose': 3,
        'errorCallbacks': 0,
        'lastCallbackAgeMs': 25,
        'activeDelegate': 'cpu',
        'lastError': null,
        'analyzerInputFps': 30.0,
        'inferenceSubmittedFps': 10.0,
        'resultCallbackFps': 9.5,
        'validPoseFps': 8.0,
        'actualAnalysisFps': 10.0,
        'droppedBeforePreprocessing': 12,
        'rejectedAsBusy': 2,
        'convertedBitmapCount': 7,
        'rotationBitmapCount': 7,
        'resultCount': 20,
        'noPoseCount': 3,
        'preprocessingP50Ms': 4,
        'preprocessingP95Ms': 8,
        'inferenceP50Ms': 45,
        'inferenceP95Ms': 80,
        'nativePipelineP50Ms': 55,
        'nativePipelineP95Ms': 95,
        'diagnosticEventFps': 5.0,
        'landmarks': <Object>[],
      }),
      throwsA(isA<SquatDetectorFailure>()),
    );
  });

  test('distinguishes callback wait from callback with no pose', () {
    final detector = MethodChannelSquatDetector(methodChannel: channel);

    final waiting = detector.parseEvent({
      'contractVersion': 1,
      'type': 'pipelineStatusChanged',
      'eventId': 'session-12345678_pipeline_1',
      'occurredAtEpochMs': 1_000,
      'squatSessionId': 'session-12345678',
      'status': 'awaitingResult',
    });
    final noPose = detector.parseEvent({
      'contractVersion': 1,
      'type': 'pipelineStatusChanged',
      'eventId': 'session-12345678_pipeline_2',
      'occurredAtEpochMs': 1_001,
      'squatSessionId': 'session-12345678',
      'status': 'noPose',
    });

    expect(
      (waiting as SquatPipelineStatusChanged).status,
      SquatPosePipelineStatus.awaitingResult,
    );
    expect(
      (noPose as SquatPipelineStatusChanged).status,
      SquatPosePipelineStatus.noPose,
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
