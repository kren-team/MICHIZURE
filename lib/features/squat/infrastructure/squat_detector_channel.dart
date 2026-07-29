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
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
  }

  SquatDetectorReady _readyEvent(
    Map<dynamic, dynamic> raw,
    String eventId,
    DateTime occurredAt,
  ) {
    if (raw['detectorType'] != 'mlkit') {
      throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      );
    }
    return SquatDetectorReady(
      eventId: eventId,
      occurredAt: occurredAt,
      squatSessionId: _sessionId(raw),
      detectorVersion: _detectorVersion(raw),
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
        raw['detectorType'] != 'mlkit' ||
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
      'showFullBody' => SquatQualityWarning.showFullBody,
      'moveFartherBack' => SquatQualityWarning.moveFartherBack,
      'moveCloser' => SquatQualityWarning.moveCloser,
      'lowLightOrConfidence' => SquatQualityWarning.lowLightOrConfidence,
      'holdStillToCalibrate' => SquatQualityWarning.holdStillToCalibrate,
      'cameraUnavailable' => SquatQualityWarning.cameraUnavailable,
      _ => throw const SquatDetectorFailure(
        SquatDetectorFailureReason.malformedEvent,
      ),
    };
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
