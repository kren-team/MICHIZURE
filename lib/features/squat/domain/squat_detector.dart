enum CameraPermissionState { granted, denied, permanentlyDenied }

enum SquatDetectorState { calibrating, standing, descending, bottom, ascending }

enum SquatQualityWarning {
  noPoseDetected,
  hipUnavailable,
  kneeUnavailable,
  ankleUnavailable,
  moveFartherBack,
  moveCloser,
  lowLightOrConfidence,
  holdStillToCalibrate,
  squatDeeper,
  tooDeep,
  cameraUnavailable,
}

enum SquatPoseSide { left, right }

enum SquatPoseTrackingStatus {
  noPose,
  hipUnavailable,
  kneeUnavailable,
  ankleUnavailable,
  confidenceInsufficient,
  valid,
}

enum SquatInferenceDelegate { gpu, cpu }

enum SquatBottomEvidencePath { kneeOnly, kneeAndHip, hipAndReversal }

enum SquatPosePipelineStatus {
  initializing,
  awaitingResult,
  noPose,
  hipUnavailable,
  kneeUnavailable,
  ankleUnavailable,
  confidenceInsufficient,
  valid,
  failed,
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

final class SquatPipelineStatusChanged extends SquatDetectorEvent {
  const SquatPipelineStatusChanged({
    required super.eventId,
    required super.occurredAt,
    required this.squatSessionId,
    required this.status,
  });

  final String squatSessionId;
  final SquatPosePipelineStatus status;
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
    required this.selectedSide,
    required this.leftHipConfidence,
    required this.leftKneeConfidence,
    required this.leftAnkleConfidence,
    required this.rightHipConfidence,
    required this.rightKneeConfidence,
    required this.rightAnkleConfidence,
    required this.kneeAngle,
    required this.normalizedHipDrop,
    required this.kneeAngularVelocity,
    required this.hipVerticalVelocity,
    required this.state,
    required this.latestRejectReason,
    required this.analysisLatencyMs,
    required this.acceptedReps,
    required this.rejectedAttempts,
    this.trackingStatus = SquatPoseTrackingStatus.noPose,
    this.pipelineStatus = SquatPosePipelineStatus.initializing,
    this.delegate,
    this.rawKneeAngle,
    this.previousState,
    this.lastTransitionReason,
    this.lastResetReason,
    this.frameDtMs,
    this.validPoseAgeMs,
    this.effectiveValidPoseFps = 0,
    this.calibrationSampleCount = 0,
    this.calibrationStatus = 'waitingForStanding',
    this.bottomReached = false,
    this.standingConfirmationDurationMs = 0,
    this.bottomConfirmationDurationMs = 0,
    this.returnStandingDurationMs = 0,
    this.currentRepDurationMs,
    this.calibratedStandingKneeAngle,
    this.standingThresholdDeg = 155,
    this.descendingThresholdDeg = 150,
    this.bottomThresholdDeg = 120,
    this.returnStandingThresholdDeg = 150,
    this.minimumAttemptKneeAngle,
    this.maximumAttemptHipDrop,
    this.kneeBendDelta,
    this.downwardMovementObserved = false,
    this.upwardMovementObserved = false,
    this.bottomEvidenceScore = 0,
    this.bottomEvidencePath,
    this.attemptStartTimestampMs,
    this.lastValidPoseTimestampMs,
    this.baselineHipY,
    this.legScale,
    this.baselineJitter,
    this.calibrationSelectedSide,
    this.sampleCount = 0,
    this.analyzerFrames = 0,
    this.inferenceSubmitted = 0,
    this.resultCallbacks = 0,
    this.resultsWithPose = 0,
    this.resultsWithoutPose = 0,
    this.errorCallbacks = 0,
    this.lastCallbackAgeMs,
    this.activeDelegate,
    this.lastError,
    this.analyzerInputFps = 0,
    this.inferenceSubmittedFps = 0,
    this.resultCallbackFps = 0,
    this.validPoseFps = 0,
    this.actualAnalysisFps = 0,
    this.requestedAnalysisWidth = 0,
    this.requestedAnalysisHeight = 0,
    this.actualAnalysisWidth,
    this.actualAnalysisHeight,
    this.droppedBeforePreprocessing = 0,
    this.rejectedAsBusy = 0,
    this.resultCount = 0,
    this.noPoseCount = 0,
    this.preprocessingP50Ms,
    this.preprocessingP95Ms,
    this.inferenceP50Ms,
    this.inferenceP95Ms,
    this.nativePipelineP50Ms,
    this.nativePipelineP95Ms,
    this.diagnosticEventFps = 0,
  });

  final String squatSessionId;
  final bool poseDetected;
  final SquatPoseSide? selectedSide;
  final double? leftHipConfidence;
  final double? leftKneeConfidence;
  final double? leftAnkleConfidence;
  final double? rightHipConfidence;
  final double? rightKneeConfidence;
  final double? rightAnkleConfidence;
  final double? kneeAngle;
  final double? rawKneeAngle;
  final double? normalizedHipDrop;
  final double? kneeAngularVelocity;
  final double? hipVerticalVelocity;
  final SquatDetectorState state;
  final SquatDetectorState? previousState;
  final String? lastTransitionReason;
  final String? latestRejectReason;
  final String? lastResetReason;
  final int? frameDtMs;
  final int? validPoseAgeMs;
  final double effectiveValidPoseFps;
  final int calibrationSampleCount;
  final String calibrationStatus;
  final bool bottomReached;
  final int standingConfirmationDurationMs;
  final int bottomConfirmationDurationMs;
  final int returnStandingDurationMs;
  final int? currentRepDurationMs;
  final double? calibratedStandingKneeAngle;
  final double standingThresholdDeg;
  final double descendingThresholdDeg;
  final double bottomThresholdDeg;
  final double returnStandingThresholdDeg;
  final double? minimumAttemptKneeAngle;
  final double? maximumAttemptHipDrop;
  final double? kneeBendDelta;
  final bool downwardMovementObserved;
  final bool upwardMovementObserved;
  final int bottomEvidenceScore;
  final SquatBottomEvidencePath? bottomEvidencePath;
  final int? attemptStartTimestampMs;
  final int? lastValidPoseTimestampMs;
  final double? baselineHipY;
  final double? legScale;
  final double? baselineJitter;
  final SquatPoseSide? calibrationSelectedSide;
  final int analysisLatencyMs;
  final int acceptedReps;
  final int rejectedAttempts;
  final SquatPoseTrackingStatus trackingStatus;
  final SquatPosePipelineStatus pipelineStatus;
  final SquatInferenceDelegate? delegate;
  final int sampleCount;
  final int analyzerFrames;
  final int inferenceSubmitted;
  final int resultCallbacks;
  final int resultsWithPose;
  final int resultsWithoutPose;
  final int errorCallbacks;
  final int? lastCallbackAgeMs;
  final SquatInferenceDelegate? activeDelegate;
  final String? lastError;
  final double analyzerInputFps;
  final double inferenceSubmittedFps;
  final double resultCallbackFps;
  final double validPoseFps;
  final double actualAnalysisFps;
  final int requestedAnalysisWidth;
  final int requestedAnalysisHeight;
  final int? actualAnalysisWidth;
  final int? actualAnalysisHeight;
  final int droppedBeforePreprocessing;
  final int rejectedAsBusy;
  final int resultCount;
  final int noPoseCount;
  final int? preprocessingP50Ms;
  final int? preprocessingP95Ms;
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
