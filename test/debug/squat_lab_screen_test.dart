import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/debug/debug_pose_fixture_channel.dart';
import 'package:michizure/debug/squat_lab_screen.dart';
import 'package:michizure/features/squat/domain/squat_detector.dart';

void main() {
  testWidgets('Squat Lab starts without Firebase or Debt state', (
    tester,
  ) async {
    final detector = _FakeLabDetector();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squatDetectorProvider.overrideWithValue(detector)],
        child: const MaterialApp(home: SquatLabScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Squat Lab（Debug）'), findsOneWidget);
    expect(find.byKey(const Key('squat-lab-permission')), findsOneWidget);
    expect(find.text('Accepted: 0'), findsOneWidget);
    expect(detector.started, isFalse);
  });

  testWidgets('known fixture action reports callback pose and landmarks', (
    tester,
  ) async {
    final detector = _FakeLabDetector();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squatDetectorProvider.overrideWithValue(detector)],
        child: MaterialApp(
          home: SquatLabScreen(fixtureGateway: _FakeFixtureGateway()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('squat-lab-run-fixture')));
    await tester.pump();

    expect(find.byKey(const Key('squat-lab-fixture-result')), findsOneWidget);
    expect(find.textContaining('true / 1 / true-true-true'), findsOneWidget);
  });

  testWidgets('debug input thumbnail is off until explicitly enabled', (
    tester,
  ) async {
    final detector = _FakeLabDetector();
    final thumbnail = _FakeThumbnailGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squatDetectorProvider.overrideWithValue(detector)],
        child: MaterialApp(home: SquatLabScreen(thumbnailGateway: thumbnail)),
      ),
    );
    await tester.pump();

    final toggle = find.byKey(const Key('squat-lab-thumbnail-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();

    expect(thumbnail.values, [true]);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('shows calibrated thresholds and attempt extrema', (
    tester,
  ) async {
    final detector = _FakeLabDetector();
    addTearDown(detector.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [squatDetectorProvider.overrideWithValue(detector)],
        child: const MaterialApp(home: SquatLabScreen()),
      ),
    );
    await tester.pump();

    detector.emit(
      SquatDetectorDiagnostics(
        eventId: 'diagnostics-1',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(1),
        squatSessionId: 'squat-lab-debug-0001',
        poseDetected: true,
        selectedSide: SquatPoseSide.left,
        leftHipConfidence: 0.9,
        leftKneeConfidence: 0.9,
        leftAnkleConfidence: 0.9,
        rightHipConfidence: null,
        rightKneeConfidence: null,
        rightAnkleConfidence: null,
        kneeAngle: 132,
        normalizedHipDrop: 0.11,
        kneeAngularVelocity: null,
        hipVerticalVelocity: null,
        state: SquatDetectorState.bottom,
        latestRejectReason: null,
        analysisLatencyMs: 50,
        acceptedReps: 0,
        rejectedAttempts: 0,
        calibratedStandingKneeAngle: 168,
        standingThresholdDeg: 143,
        descendingThresholdDeg: 148,
        bottomThresholdDeg: 144,
        returnStandingThresholdDeg: 143,
        minimumAttemptKneeAngle: 132,
        maximumAttemptHipDrop: 0.11,
        kneeBendDelta: 36,
        downwardMovementObserved: true,
        bottomEvidenceScore: 5,
        bottomEvidencePath: SquatBottomEvidencePath.kneeOnly,
        baselineHipY: 0.25,
        legScale: 0.5,
        baselineJitter: 0.01,
        calibrationSelectedSide: SquatPoseSide.left,
        calibrationSampleCount: 2,
        calibrationStatus: 'COMPLETE',
        strongStandingCandidateCount: 2,
        provisionalStandingAngle: 176.7,
        calibrationMedianAngle: 173.9,
        calibrationAngleRange: 5.6,
        calibrationWindowAgeMs: 500,
        calibrationTimeoutMs: 8_000,
        calibrationQualityPath: 'ANGLE_CONFIDENCE_FALLBACK',
        candidateBufferPreserved: true,
        autoCalibratedOnDescent: true,
        standingBaselineSource: 'AUTO_CALIBRATED_ON_DESCENT',
        requestedAnalysisWidth: 320,
        requestedAnalysisHeight: 240,
        actualAnalysisWidth: 320,
        actualAnalysisHeight: 240,
        convertedBitmapCount: 7,
        rotationBitmapCount: 6,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Calibrated standing knee: 168.0'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Threshold standing / descent / bottom / return: 143.00 / 148.00 / 144.00 / 143.00',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Attempt min knee / max hip drop: 132.00 / 0.110'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Knee bend / movement down-up: 36.00 / true-false'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Bottom evidence: 5 / KNEE_ONLY'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Analysis requested / actual: 320×240 / 320×240'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Bitmap converted / rotated: 7 / 6'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Calibration: COMPLETE (2/2, strong 2)'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Buffer preserved / auto descent / baseline: true / true',
      ),
      findsOneWidget,
    );
  });
}

final class _FakeLabDetector implements SquatDetector {
  var started = false;
  final _events = StreamController<SquatDetectorEvent>.broadcast(sync: true);

  @override
  Stream<SquatDetectorEvent> get events => _events.stream;

  void emit(SquatDetectorEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();

  @override
  Future<CameraPermissionState> getCameraPermissionState() async =>
      CameraPermissionState.denied;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<CameraPermissionState> requestCameraPermission() async =>
      CameraPermissionState.denied;

  @override
  Future<void> start(SquatDetectorSession session) async {
    started = true;
  }

  @override
  Future<void> stop({String? squatSessionId}) async {}
}

final class _FakeFixtureGateway implements DebugPoseFixtureGateway {
  @override
  Future<DebugPoseFixtureResult> run() async {
    return const DebugPoseFixtureResult(
      callbackDelivered: true,
      poseCount: 1,
      hipAvailable: true,
      kneeAvailable: true,
      ankleAvailable: true,
      errorCode: null,
    );
  }
}

final class _FakeThumbnailGateway implements DebugPoseThumbnailGateway {
  final values = <bool>[];

  @override
  Future<void> setEnabled(bool enabled) async => values.add(enabled);
}
