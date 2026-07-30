enum CameraPermissionState { granted, denied, permanentlyDenied }

enum SquatDetectorState { calibrating, standing, descending, bottom, ascending }

enum SquatQualityWarning {
  noPoseDetected,
  hipUnavailable,
  kneeUnavailable,
  moveFartherBack,
  moveCloser,
  lowLightOrConfidence,
  holdStillToCalibrate,
  cameraUnavailable,
}

enum SquatTrackingStatus {
  noPose,
  hipUnavailable,
  kneeUnavailable,
  confidenceInsufficient,
  valid,
}

enum SquatPoseSide { left, right }

enum SquatInferenceDelegate { gpu, cpu }

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
    required this.delegate,
  });

  final String squatSessionId;
  final String detectorVersion;
  final SquatInferenceDelegate delegate;
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

final class SquatDetectorDiagnostics extends SquatDetectorEvent {
  const SquatDetectorDiagnostics({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.poseDetected,
    required this.trackingStatus,
    required this.selectedSide,
    required this.leftHipConfidence,
    required this.leftKneeConfidence,
    required this.leftAnkleConfidence,
    required this.rightHipConfidence,
    required this.rightKneeConfidence,
    required this.rightAnkleConfidence,
    required this.normalizedVerticalGap,
    required this.normalizedHipDrop,
    required this.state,
    required this.latestRejectReason,
    required this.analysisLatencyMs,
    required this.acceptedReps,
    required this.rejectedAttempts,
    this.delegate,
    this.sampleCount = 0,
    this.actualAnalysisFps = 0,
    this.droppedBeforePreprocessing = 0,
    this.rejectedAsBusy = 0,
    this.resultCount = 0,
    this.noPoseCount = 0,
    this.inferenceP50Ms,
    this.inferenceP95Ms,
    this.nativePipelineP50Ms,
    this.nativePipelineP95Ms,
    this.diagnosticEventFps = 0,
  });

  final String squatSessionId;
  final bool poseDetected;
  final SquatTrackingStatus trackingStatus;
  final SquatPoseSide? selectedSide;
  final double? leftHipConfidence;
  final double? leftKneeConfidence;
  final double? leftAnkleConfidence;
  final double? rightHipConfidence;
  final double? rightKneeConfidence;
  final double? rightAnkleConfidence;
  final double? normalizedVerticalGap;
  final double? normalizedHipDrop;
  final SquatDetectorState state;
  final String? latestRejectReason;
  final int analysisLatencyMs;
  final int acceptedReps;
  final int rejectedAttempts;
  final SquatInferenceDelegate? delegate;
  final int sampleCount;
  final double actualAnalysisFps;
  final int droppedBeforePreprocessing;
  final int rejectedAsBusy;
  final int resultCount;
  final int noPoseCount;
  final int? inferenceP50Ms;
  final int? inferenceP95Ms;
  final int? nativePipelineP50Ms;
  final int? nativePipelineP95Ms;
  final double diagnosticEventFps;
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
