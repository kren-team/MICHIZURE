import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
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
