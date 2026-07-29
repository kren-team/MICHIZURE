enum CameraPermissionState { granted, denied, permanentlyDenied }

enum SquatDetectorState { calibrating, standing, descending, bottom, ascending }

enum SquatQualityWarning {
  showFullBody,
  moveFartherBack,
  moveCloser,
  lowLightOrConfidence,
  holdStillToCalibrate,
  cameraUnavailable,
}

enum SquatDetectorFailureReason {
  permissionDenied,
  permissionPermanentlyDenied,
  cameraUnavailable,
  sessionConflict,
  contractMismatch,
  nativeUnavailable,
  malformedEvent,
  unknown,
}

final class SquatDetectorFailure implements Exception {
  const SquatDetectorFailure(this.reason);

  final SquatDetectorFailureReason reason;
}

final class SquatDetectorSession {
  const SquatDetectorSession({
    required this.squatSessionId,
    required this.debtId,
  });

  final String squatSessionId;
  final String debtId;
}

sealed class SquatDetectorEvent {
  const SquatDetectorEvent({required this.eventId, required this.occurredAt});

  final String eventId;
  final DateTime occurredAt;
}

final class SquatDetectorReady extends SquatDetectorEvent {
  const SquatDetectorReady({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.detectorVersion,
  });

  final String squatSessionId;
  final String detectorVersion;
}

final class SquatStateChanged extends SquatDetectorEvent {
  const SquatStateChanged({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.state,
    required this.analysisLatencyMs,
  });

  final String squatSessionId;
  final SquatDetectorState state;
  final int analysisLatencyMs;
}

final class SquatQualityChanged extends SquatDetectorEvent {
  const SquatQualityChanged({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.warning,
    required this.analysisLatencyMs,
  });

  final String squatSessionId;
  final SquatQualityWarning? warning;
  final int analysisLatencyMs;
}

final class SquatRepCompleted extends SquatDetectorEvent {
  const SquatRepCompleted({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.sequence,
    required this.detectorVersion,
    required this.frameObservedElapsedMs,
    required this.uiEmittedElapsedMs,
    required this.analysisLatencyMs,
  });

  final String squatSessionId;
  final int sequence;
  final String detectorVersion;
  final int frameObservedElapsedMs;
  final int uiEmittedElapsedMs;
  final int analysisLatencyMs;
}

final class SquatDetectorFailed extends SquatDetectorEvent {
  const SquatDetectorFailed({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.code,
  });

  final String squatSessionId;
  final String code;
}

abstract interface class SquatDetector {
  Stream<SquatDetectorEvent> get events;

  Future<CameraPermissionState> getCameraPermissionState();

  Future<CameraPermissionState> requestCameraPermission();

  Future<void> openAppSettings();

  Future<void> start(SquatDetectorSession session);

  Future<void> stop({String? squatSessionId});
}

abstract interface class SquatSessionIdGenerator {
  String generate();
}
