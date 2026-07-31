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
}

final class _FakeLabDetector implements SquatDetector {
  var started = false;

  @override
  Stream<SquatDetectorEvent> get events => const Stream.empty();

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
