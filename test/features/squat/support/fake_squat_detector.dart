import 'dart:async';

import 'package:michizure/features/squat/domain/squat_detector.dart';

final class FakeSquatDetector implements SquatDetector {
  final controller = StreamController<SquatDetectorEvent>.broadcast();
  CameraPermissionState permission = CameraPermissionState.granted;
  SquatDetectorFailure? failure;
  Completer<void>? startBlocker;
  final List<SquatDetectorSession> starts = [];
  final List<String?> stops = [];

  @override
  Stream<SquatDetectorEvent> get events => controller.stream;

  @override
  Future<CameraPermissionState> getCameraPermissionState() async {
    if (failure case final value?) throw value;
    return permission;
  }

  @override
  Future<CameraPermissionState> requestCameraPermission() async {
    if (failure case final value?) throw value;
    return permission;
  }

  @override
  Future<void> openAppSettings() async {
    if (failure case final value?) throw value;
  }

  @override
  Future<void> start(SquatDetectorSession session) async {
    if (failure case final value?) throw value;
    starts.add(session);
    await startBlocker?.future;
  }

  @override
  Future<void> stop({String? squatSessionId}) async {
    if (failure case final value?) throw value;
    stops.add(squatSessionId);
  }

  void emit(SquatDetectorEvent event) => controller.add(event);

  Future<void> close() => controller.close();
}

final class FixedSquatSessionIdGenerator implements SquatSessionIdGenerator {
  const FixedSquatSessionIdGenerator(this.value);

  final String value;

  @override
  String generate() => value;
}
