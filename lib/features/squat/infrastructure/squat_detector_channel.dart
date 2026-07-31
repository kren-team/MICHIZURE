import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/squat_detector.dart';

final class MethodChannelSquatDetector implements SquatDetector {
  MethodChannelSquatDetector({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  static const int contractVersion = 1;
  static const String previewViewType = 'com.kren.michizure/pose_preview/v1';
  static const String poseSource = String.fromEnvironment(
    'POSE_SOURCE',
    defaultValue: 'local',
  );
  static const Map<String, Object?> previewCreationParams = {
    'poseSource': poseSource,
  };
  static const String _methodChannelName =
      'com.kren.michizure/squat_control/v1';
  static const String _eventChannelName = 'com.kren.michizure/squat_events/v1';
  static const Duration _timeout = Duration(seconds: 8);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<SquatDetectorEvent>? _events;

  @override
  Stream<SquatDetectorEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream(const {'contractVersion': contractVersion})
        .map(parseEvent)
        .handleError((Object error) {
          if (error is SquatDetectorFailure) throw error;
          throw const SquatDetectorFailure(
            SquatDetectorFailureReason.nativeUnavailable,
          );
        })
        .asBroadcastStream();
  }

  @override
  Future<CameraPermissionState> getCameraPermissionState() async {
    final payload = await _invoke('getCameraPermissionState');
    return _parsePermission(payload);
  }

  @override
  Future<CameraPermissionState> requestCameraPermission() async {
    final payload = await _invoke('requestCameraPermission');
    return _parsePermission(payload);
  }

  @override
  Future<void> openAppSettings() async {
    await _invoke('openAppSettings');
  }

  @override
  Future<void> start(SquatDetectorSession session) async {
    await _invoke('startSession', {
      'squatSessionId': session.squatSessionId,
      'debtId': session.debtId,
    });
  }

  @override
  Future<void> stop({String? squatSessionId}) async {
    await _invoke(
      'stopSession',
      squatSessionId == null ? const {} : {'squatSessionId': squatSessionId},
    );
  }

  Future<Map<Object?, Object?>> _invoke(
    String method, [
    Map<String, Object?> values = const {},
  ]) async {
    try {
      final result = await _methodChannel
          .invokeMapMethod<Object?, Object?>(method, {
            'contractVersion': contractVersion,
            'poseSource': poseSource,
            ...values,
          })
          .timeout(_timeout);
      if (result == null || result['contractVersion'] != contractVersion) {
        throw const SquatDetectorFailure(
          SquatDetectorFailureReason.contractMismatch,
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw SquatDetectorFailure(_failureReason(error.code));
    } on TimeoutException {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.nativeUnavailable,
      );
    }
  }

  CameraPermissionState _parsePermission(Map<Object?, Object?> payload) {
    return switch (payload['state']) {
      'granted' => CameraPermissionState.granted,
      'denied' => CameraPermissionState.denied,
      'permanentlyDenied' => CameraPermissionState.permanentlyDenied,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.contractMismatch,
      ),
    };
  }

  SquatDetectorEvent parseEvent(dynamic raw) {
    if (raw is! Map ||
        raw['contractVersion'] != contractVersion ||
        raw['eventId'] is! String ||
        raw['occurredAtEpochMs'] is! int) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    final eventId = raw['eventId'] as String;
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      raw['occurredAtEpochMs'] as int,
      isUtc: true,
    );
    if (eventId.isEmpty) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    final allowed = switch (raw['type']) {
      'detectorReady' => {
        ..._baseEventFields,
        'squatSessionId',
        'detectorType',
        'detectorVersion',
        'delegate',
      },
      'calibrating' => {
        ..._baseEventFields,
        'squatSessionId',
        'state',
        'quality',
      },
      'stateChanged' => {
        ..._baseEventFields,
        'squatSessionId',
        'state',
        'analysisLatencyMs',
      },
      'pipelineStatusChanged' => {
        ..._baseEventFields,
        'squatSessionId',
        'status',
      },
      'qualityWarning' => {
        ..._baseEventFields,
        'squatSessionId',
        'quality',
        'analysisLatencyMs',
      },
      'repCompleted' => {
        ..._baseEventFields,
        'squatSessionId',
        'sequence',
        'detectorType',
        'detectorVersion',
        'frameObservedElapsedMs',
        'uiEmittedElapsedMs',
        'analysisLatencyMs',
      },
      'detectorError' => {..._baseEventFields, 'squatSessionId', 'code'},
      'diagnostics' => {
        ..._baseEventFields,
        'squatSessionId',
        'poseDetected',
        'pipelineStatus',
        'trackingStatus',
        'selectedSide',
        'leftHipConfidence',
        'leftKneeConfidence',
        'leftAnkleConfidence',
        'rightHipConfidence',
        'rightKneeConfidence',
        'rightAnkleConfidence',
        'rawKneeAngle',
        'kneeAngle',
        'normalizedHipDrop',
        'kneeAngularVelocity',
        'hipVerticalVelocity',
        'state',
        'previousState',
        'lastTransitionReason',
        'latestRejectReason',
        'lastResetReason',
        'frameDtMs',
        'validPoseAgeMs',
        'effectiveValidPoseFps',
        'calibrationSampleCount',
        'calibrationStatus',
        'strongStandingCandidateCount',
        'provisionalStandingAngle',
        'calibrationMedianAngle',
        'calibrationAngleRange',
        'calibrationWindowAgeMs',
        'calibrationTimeoutMs',
        'calibrationQualityPath',
        'lastCalibrationRejectReason',
        'candidateBufferPreserved',
        'autoCalibratedOnDescent',
        'standingBaselineSource',
        'bottomReached',
        'standingConfirmationDurationMs',
        'bottomConfirmationDurationMs',
        'returnStandingDurationMs',
        'currentRepDurationMs',
        'calibratedStandingKneeAngle',
        'standingThresholdDeg',
        'descendingThresholdDeg',
        'bottomThresholdDeg',
        'returnStandingThresholdDeg',
        'minimumAttemptKneeAngle',
        'maximumAttemptHipDrop',
        'kneeBendDelta',
        'downwardMovementObserved',
        'upwardMovementObserved',
        'bottomEvidenceScore',
        'bottomEvidencePath',
        'attemptStartTimestampMs',
        'lastValidPoseTimestampMs',
        'baselineHipY',
        'legScale',
        'baselineJitter',
        'calibrationSelectedSide',
        'analysisLatencyMs',
        'acceptedReps',
        'rejectedAttempts',
        'delegate',
        'sampleCount',
        'analyzerFrames',
        'inferenceSubmitted',
        'resultCallbacks',
        'resultsWithPose',
        'resultsWithoutPose',
        'errorCallbacks',
        'lastCallbackAgeMs',
        'activeDelegate',
        'lastError',
        'analyzerInputFps',
        'inferenceSubmittedFps',
        'resultCallbackFps',
        'validPoseFps',
        'actualAnalysisFps',
        'requestedAnalysisWidth',
        'requestedAnalysisHeight',
        'actualAnalysisWidth',
        'actualAnalysisHeight',
        'droppedBeforePreprocessing',
        'rejectedAsBusy',
        'convertedBitmapCount',
        'rotationBitmapCount',
        'resultCount',
        'noPoseCount',
        'preprocessingP50Ms',
        'preprocessingP95Ms',
        'inferenceP50Ms',
        'inferenceP95Ms',
        'nativePipelineP50Ms',
        'nativePipelineP95Ms',
        'diagnosticEventFps',
      },
      _ => const <String>{},
    };
    if (allowed.isEmpty || raw.keys.any((key) => !allowed.contains(key))) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return switch (raw['type']) {
      'detectorReady' => _readyEvent(raw, eventId, occurredAt),
      'calibrating' || 'stateChanged' => SquatStateChanged(
        eventId: eventId,
        occurredAt: occurredAt,
        squatSessionId: _sessionId(raw),
        state: _state(_string(raw, 'state')),
        analysisLatencyMs: _nonNegativeInt(
          raw,
          'analysisLatencyMs',
          fallback: 0,
        ),
      ),
      'pipelineStatusChanged' => SquatPipelineStatusChanged(
        eventId: eventId,
        occurredAt: occurredAt,
        squatSessionId: _sessionId(raw),
        status: _pipelineStatus(_string(raw, 'status')),
      ),
      'qualityWarning' => SquatQualityChanged(
        eventId: eventId,
        occurredAt: occurredAt,
        squatSessionId: _sessionId(raw),
        warning: _quality(raw['quality']),
        analysisLatencyMs: _nonNegativeInt(raw, 'analysisLatencyMs'),
      ),
      'repCompleted' => _repEvent(raw, eventId, occurredAt),
      'detectorError' => SquatDetectorFailed(
        eventId: eventId,
        occurredAt: occurredAt,
        squatSessionId: _sessionId(raw),
        code: _string(raw, 'code'),
      ),
      'diagnostics' => _diagnosticsEvent(raw, eventId, occurredAt),
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatDetectorDiagnostics _diagnosticsEvent(
    Map<dynamic, dynamic> raw,
    String eventId,
    DateTime occurredAt,
  ) {
    final poseDetected = raw['poseDetected'];
    final latestRejectReason = raw['latestRejectReason'];
    final lastTransitionReason = raw['lastTransitionReason'];
    final lastResetReason = raw['lastResetReason'];
    final calibrationStatus = raw['calibrationStatus'];
    final calibrationQualityPath = raw['calibrationQualityPath'];
    final lastCalibrationRejectReason = raw['lastCalibrationRejectReason'];
    final standingBaselineSource = raw['standingBaselineSource'];
    if (poseDetected is! bool ||
        !_isNullableDiagnosticCode(latestRejectReason) ||
        !_isNullableDiagnosticCode(lastTransitionReason) ||
        !_isNullableDiagnosticCode(lastResetReason) ||
        calibrationStatus is! String ||
        calibrationStatus.isEmpty ||
        calibrationStatus.length > 64 ||
        !_isNullableDiagnosticCode(calibrationQualityPath) ||
        !_isNullableDiagnosticCode(lastCalibrationRejectReason) ||
        !_isNullableDiagnosticCode(standingBaselineSource) ||
        raw['candidateBufferPreserved'] is! bool ||
        raw['autoCalibratedOnDescent'] is! bool ||
        raw['bottomReached'] is! bool ||
        raw['downwardMovementObserved'] is! bool ||
        raw['upwardMovementObserved'] is! bool) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return SquatDetectorDiagnostics(
      eventId: eventId,
      occurredAt: occurredAt,
      squatSessionId: _sessionId(raw),
      poseDetected: poseDetected,
      trackingStatus: _trackingStatus(_string(raw, 'trackingStatus')),
      pipelineStatus: _pipelineStatus(_string(raw, 'pipelineStatus')),
      selectedSide: switch (raw['selectedSide']) {
        null => null,
        'left' => SquatPoseSide.left,
        'right' => SquatPoseSide.right,
        _ => throw const SquatDetectorFailure(
          SquatDetectorFailureReason.malformedEvent,
        ),
      },
      leftHipConfidence: _nullableDouble(raw, 'leftHipConfidence'),
      leftKneeConfidence: _nullableDouble(raw, 'leftKneeConfidence'),
      leftAnkleConfidence: _nullableDouble(raw, 'leftAnkleConfidence'),
      rightHipConfidence: _nullableDouble(raw, 'rightHipConfidence'),
      rightKneeConfidence: _nullableDouble(raw, 'rightKneeConfidence'),
      rightAnkleConfidence: _nullableDouble(raw, 'rightAnkleConfidence'),
      rawKneeAngle: _nullableDouble(raw, 'rawKneeAngle'),
      kneeAngle: _nullableDouble(raw, 'kneeAngle'),
      normalizedHipDrop: _nullableDouble(raw, 'normalizedHipDrop'),
      kneeAngularVelocity: _nullableDouble(raw, 'kneeAngularVelocity'),
      hipVerticalVelocity: _nullableDouble(raw, 'hipVerticalVelocity'),
      state: _state(_string(raw, 'state')),
      previousState: switch (raw['previousState']) {
        null => null,
        final String value => _state(value),
        _ => throw const SquatDetectorFailure(
          SquatDetectorFailureReason.malformedEvent,
        ),
      },
      lastTransitionReason: lastTransitionReason as String?,
      latestRejectReason: latestRejectReason as String?,
      lastResetReason: lastResetReason as String?,
      frameDtMs: _nullableInt(raw, 'frameDtMs'),
      validPoseAgeMs: _nullableNonNegativeInt(raw, 'validPoseAgeMs'),
      effectiveValidPoseFps: _nonNegativeDouble(raw, 'effectiveValidPoseFps'),
      calibrationSampleCount: _nonNegativeInt(raw, 'calibrationSampleCount'),
      calibrationStatus: calibrationStatus,
      strongStandingCandidateCount: _nonNegativeInt(
        raw,
        'strongStandingCandidateCount',
      ),
      provisionalStandingAngle: _nullableDouble(
        raw,
        'provisionalStandingAngle',
      ),
      calibrationMedianAngle: _nullableDouble(raw, 'calibrationMedianAngle'),
      calibrationAngleRange: _nullableDouble(raw, 'calibrationAngleRange'),
      calibrationWindowAgeMs: _nullableNonNegativeInt(
        raw,
        'calibrationWindowAgeMs',
      ),
      calibrationTimeoutMs: _nonNegativeInt(raw, 'calibrationTimeoutMs'),
      calibrationQualityPath: calibrationQualityPath as String?,
      lastCalibrationRejectReason: lastCalibrationRejectReason as String?,
      candidateBufferPreserved: raw['candidateBufferPreserved'] as bool,
      autoCalibratedOnDescent: raw['autoCalibratedOnDescent'] as bool,
      standingBaselineSource: standingBaselineSource as String?,
      bottomReached: raw['bottomReached'] as bool,
      standingConfirmationDurationMs: _nonNegativeInt(
        raw,
        'standingConfirmationDurationMs',
      ),
      bottomConfirmationDurationMs: _nonNegativeInt(
        raw,
        'bottomConfirmationDurationMs',
      ),
      returnStandingDurationMs: _nonNegativeInt(
        raw,
        'returnStandingDurationMs',
      ),
      currentRepDurationMs: _nullableNonNegativeInt(
        raw,
        'currentRepDurationMs',
      ),
      calibratedStandingKneeAngle: _nullableDouble(
        raw,
        'calibratedStandingKneeAngle',
      ),
      standingThresholdDeg: _nonNegativeDouble(raw, 'standingThresholdDeg'),
      descendingThresholdDeg: _nonNegativeDouble(raw, 'descendingThresholdDeg'),
      bottomThresholdDeg: _nonNegativeDouble(raw, 'bottomThresholdDeg'),
      returnStandingThresholdDeg: _nonNegativeDouble(
        raw,
        'returnStandingThresholdDeg',
      ),
      minimumAttemptKneeAngle: _nullableDouble(raw, 'minimumAttemptKneeAngle'),
      maximumAttemptHipDrop: _nullableDouble(raw, 'maximumAttemptHipDrop'),
      kneeBendDelta: _nullableDouble(raw, 'kneeBendDelta'),
      downwardMovementObserved: raw['downwardMovementObserved'] as bool,
      upwardMovementObserved: raw['upwardMovementObserved'] as bool,
      bottomEvidenceScore: _nonNegativeInt(raw, 'bottomEvidenceScore'),
      bottomEvidencePath: _bottomEvidencePath(raw['bottomEvidencePath']),
      attemptStartTimestampMs: _nullableNonNegativeInt(
        raw,
        'attemptStartTimestampMs',
      ),
      lastValidPoseTimestampMs: _nullableNonNegativeInt(
        raw,
        'lastValidPoseTimestampMs',
      ),
      baselineHipY: _nullableDouble(raw, 'baselineHipY'),
      legScale: _nullableDouble(raw, 'legScale'),
      baselineJitter: _nullableDouble(raw, 'baselineJitter'),
      calibrationSelectedSide: switch (raw['calibrationSelectedSide']) {
        null => null,
        'left' => SquatPoseSide.left,
        'right' => SquatPoseSide.right,
        _ => throw const SquatDetectorFailure(
          SquatDetectorFailureReason.malformedEvent,
        ),
      },
      analysisLatencyMs: _nonNegativeInt(raw, 'analysisLatencyMs'),
      acceptedReps: _nonNegativeInt(raw, 'acceptedReps'),
      rejectedAttempts: _nonNegativeInt(raw, 'rejectedAttempts'),
      delegate: _delegate(raw['delegate']),
      sampleCount: _nonNegativeInt(raw, 'sampleCount'),
      analyzerFrames: _nonNegativeInt(raw, 'analyzerFrames'),
      inferenceSubmitted: _nonNegativeInt(raw, 'inferenceSubmitted'),
      resultCallbacks: _nonNegativeInt(raw, 'resultCallbacks'),
      resultsWithPose: _nonNegativeInt(raw, 'resultsWithPose'),
      resultsWithoutPose: _nonNegativeInt(raw, 'resultsWithoutPose'),
      errorCallbacks: _nonNegativeInt(raw, 'errorCallbacks'),
      lastCallbackAgeMs: _nullableNonNegativeInt(raw, 'lastCallbackAgeMs'),
      activeDelegate: _delegate(raw['activeDelegate']),
      lastError: _nullableErrorCode(raw['lastError']),
      analyzerInputFps: _nonNegativeDouble(raw, 'analyzerInputFps'),
      inferenceSubmittedFps: _nonNegativeDouble(raw, 'inferenceSubmittedFps'),
      resultCallbackFps: _nonNegativeDouble(raw, 'resultCallbackFps'),
      validPoseFps: _nonNegativeDouble(raw, 'validPoseFps'),
      actualAnalysisFps: _nonNegativeDouble(raw, 'actualAnalysisFps'),
      requestedAnalysisWidth: _nonNegativeInt(
        raw,
        'requestedAnalysisWidth',
        fallback: 0,
      ),
      requestedAnalysisHeight: _nonNegativeInt(
        raw,
        'requestedAnalysisHeight',
        fallback: 0,
      ),
      actualAnalysisWidth: _nullableNonNegativeInt(raw, 'actualAnalysisWidth'),
      actualAnalysisHeight: _nullableNonNegativeInt(
        raw,
        'actualAnalysisHeight',
      ),
      droppedBeforePreprocessing: _nonNegativeInt(
        raw,
        'droppedBeforePreprocessing',
      ),
      rejectedAsBusy: _nonNegativeInt(raw, 'rejectedAsBusy'),
      convertedBitmapCount: _nonNegativeInt(raw, 'convertedBitmapCount'),
      rotationBitmapCount: _nonNegativeInt(raw, 'rotationBitmapCount'),
      resultCount: _nonNegativeInt(raw, 'resultCount'),
      noPoseCount: _nonNegativeInt(raw, 'noPoseCount'),
      preprocessingP50Ms: _nullableNonNegativeInt(raw, 'preprocessingP50Ms'),
      preprocessingP95Ms: _nullableNonNegativeInt(raw, 'preprocessingP95Ms'),
      inferenceP50Ms: _nullableNonNegativeInt(raw, 'inferenceP50Ms'),
      inferenceP95Ms: _nullableNonNegativeInt(raw, 'inferenceP95Ms'),
      nativePipelineP50Ms: _nullableNonNegativeInt(raw, 'nativePipelineP50Ms'),
      nativePipelineP95Ms: _nullableNonNegativeInt(raw, 'nativePipelineP95Ms'),
      diagnosticEventFps: _nonNegativeDouble(raw, 'diagnosticEventFps'),
    );
  }

  SquatDetectorReady _readyEvent(
    Map<dynamic, dynamic> raw,
    String eventId,
    DateTime occurredAt,
  ) {
    if (raw['detectorType'] != 'mediapipe') {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return SquatDetectorReady(
      eventId: eventId,
      occurredAt: occurredAt,
      squatSessionId: _sessionId(raw),
      detectorVersion: _detectorVersion(raw),
      delegate: _delegate(raw['delegate']),
    );
  }

  SquatRepCompleted _repEvent(
    Map<dynamic, dynamic> raw,
    String eventId,
    DateTime occurredAt,
  ) {
    final sessionId = _sessionId(raw);
    final sequence = _positiveInt(raw, 'sequence');
    if (sequence > 999999999 ||
        raw['detectorType'] != 'mediapipe' ||
        eventId != '${sessionId}_$sequence') {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return SquatRepCompleted(
      eventId: eventId,
      occurredAt: occurredAt,
      squatSessionId: sessionId,
      sequence: sequence,
      detectorVersion: _detectorVersion(raw),
      frameObservedElapsedMs: _nonNegativeInt(raw, 'frameObservedElapsedMs'),
      uiEmittedElapsedMs: _nonNegativeInt(raw, 'uiEmittedElapsedMs'),
      analysisLatencyMs: _nonNegativeInt(raw, 'analysisLatencyMs'),
    );
  }

  String _sessionId(Map<dynamic, dynamic> raw) {
    final value = _string(raw, 'squatSessionId');
    if (!_sessionIdPattern.hasMatch(value)) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  String _detectorVersion(Map<dynamic, dynamic> raw) {
    final value = _string(raw, 'detectorVersion');
    if (!_detectorVersionPattern.hasMatch(value)) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  String _string(Map<dynamic, dynamic> map, String key, {String? fallback}) {
    final value = map[key] ?? fallback;
    if (value is! String || value.isEmpty) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  int _positiveInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is! int || value <= 0) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  int _nonNegativeInt(Map<dynamic, dynamic> map, String key, {int? fallback}) {
    final value = map[key] ?? fallback;
    if (value is! int || value < 0) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  int? _nullableNonNegativeInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  int? _nullableInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! int) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  bool _isNullableDiagnosticCode(Object? value) =>
      value == null ||
      (value is String && value.isNotEmpty && value.length <= 64);

  double _nonNegativeDouble(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is! num || !value.isFinite || value < 0) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value.toDouble();
  }

  SquatInferenceDelegate _delegate(Object? value) {
    return switch (value) {
      'gpu' => SquatInferenceDelegate.gpu,
      'cpu' => SquatInferenceDelegate.cpu,
      'host' => SquatInferenceDelegate.host,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatBottomEvidencePath? _bottomEvidencePath(Object? value) {
    return switch (value) {
      null => null,
      'KNEE_ONLY' => SquatBottomEvidencePath.kneeOnly,
      'KNEE_AND_HIP' => SquatBottomEvidencePath.kneeAndHip,
      'HIP_AND_REVERSAL' => SquatBottomEvidencePath.hipAndReversal,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  double? _nullableDouble(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value.toDouble();
  }

  SquatDetectorState _state(String value) {
    return switch (value) {
      'calibrating' => SquatDetectorState.calibrating,
      'standing' => SquatDetectorState.standing,
      'descending' => SquatDetectorState.descending,
      'bottom' => SquatDetectorState.bottom,
      'ascending' => SquatDetectorState.ascending,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatQualityWarning? _quality(dynamic value) {
    return switch (value) {
      null => null,
      'noPoseDetected' => SquatQualityWarning.noPoseDetected,
      'hipUnavailable' => SquatQualityWarning.hipUnavailable,
      'kneeUnavailable' => SquatQualityWarning.kneeUnavailable,
      'ankleUnavailable' => SquatQualityWarning.ankleUnavailable,
      'moveFartherBack' => SquatQualityWarning.moveFartherBack,
      'moveCloser' => SquatQualityWarning.moveCloser,
      'lowLightOrConfidence' => SquatQualityWarning.lowLightOrConfidence,
      'holdStillToCalibrate' => SquatQualityWarning.holdStillToCalibrate,
      'squatDeeper' => SquatQualityWarning.squatDeeper,
      'tooDeep' => SquatQualityWarning.tooDeep,
      'cameraUnavailable' => SquatQualityWarning.cameraUnavailable,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatPoseTrackingStatus _trackingStatus(String value) {
    return switch (value) {
      'noPose' => SquatPoseTrackingStatus.noPose,
      'hipUnavailable' => SquatPoseTrackingStatus.hipUnavailable,
      'kneeUnavailable' => SquatPoseTrackingStatus.kneeUnavailable,
      'ankleUnavailable' => SquatPoseTrackingStatus.ankleUnavailable,
      'confidenceInsufficient' =>
        SquatPoseTrackingStatus.confidenceInsufficient,
      'valid' => SquatPoseTrackingStatus.valid,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatPosePipelineStatus _pipelineStatus(String value) {
    return switch (value) {
      'initializing' => SquatPosePipelineStatus.initializing,
      'awaitingResult' => SquatPosePipelineStatus.awaitingResult,
      'noPose' => SquatPosePipelineStatus.noPose,
      'hipUnavailable' => SquatPosePipelineStatus.hipUnavailable,
      'kneeUnavailable' => SquatPosePipelineStatus.kneeUnavailable,
      'ankleUnavailable' => SquatPosePipelineStatus.ankleUnavailable,
      'confidenceInsufficient' =>
        SquatPosePipelineStatus.confidenceInsufficient,
      'valid' => SquatPosePipelineStatus.valid,
      'failed' => SquatPosePipelineStatus.failed,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  String? _nullableErrorCode(Object? value) {
    if (value == null) return null;
    if (value is! String ||
        value.isEmpty ||
        value.length > 64 ||
        !RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return value;
  }

  SquatDetectorFailureReason _failureReason(String code) {
    return switch (code) {
      'cameraPermissionDenied' => SquatDetectorFailureReason.permissionDenied,
      'cameraPermissionPermanentlyDenied' =>
        SquatDetectorFailureReason.permissionPermanentlyDenied,
      'cameraUnavailable' => SquatDetectorFailureReason.cameraUnavailable,
      'sessionConflict' => SquatDetectorFailureReason.sessionConflict,
      'channelContractMismatch' => SquatDetectorFailureReason.contractMismatch,
      'nativeUnavailable' => SquatDetectorFailureReason.nativeUnavailable,
      _ => SquatDetectorFailureReason.unknown,
    };
  }

  static const Set<String> _baseEventFields = {
    'contractVersion',
    'type',
    'eventId',
    'occurredAtEpochMs',
  };
  static final RegExp _sessionIdPattern = RegExp(r'^[A-Za-z0-9-]{16,64}$');
  static final RegExp _detectorVersionPattern = RegExp(
    r'^[A-Za-z0-9._-]{1,40}$',
  );
}
