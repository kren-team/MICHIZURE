import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/native_task_guard.dart';
import '../domain/task_session.dart';

const String taskGuardMethodChannelName =
    'com.kren.michizure/device_control/v1';
const String taskEventChannelName = 'com.kren.michizure/task_events/v1';
const int taskGuardContractVersion = 1;

final class MethodChannelNativeTaskGuard implements NativeTaskGuard {
  MethodChannelNativeTaskGuard({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Duration? timeout,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(taskGuardMethodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(taskEventChannelName),
       _timeout = timeout ?? const Duration(seconds: 5);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Duration _timeout;

  static const _baseArguments = <String, Object?>{
    'contractVersion': taskGuardContractVersion,
  };

  @override
  Stream<NativeTaskEvent> watchEvents() {
    return _eventChannel
        .receiveBroadcastStream(_baseArguments)
        .map(nativeTaskEventFromWire)
        .handleError((Object error) {
          if (error is NativeTaskGuardFailure) {
            throw error;
          }
          if (error is PlatformException) {
            throw NativeTaskGuardFailure(_failureKindForCode(error.code));
          }
          throw const NativeTaskGuardFailure(
            NativeTaskGuardFailureKind.unknown,
          );
        });
  }

  @override
  Future<NativeTaskGuardState> start(TaskSession task) async {
    if (task.status != TaskSessionStatus.running) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.invalidData,
      );
    }
    final response = await _invokeMap('startTaskGuard', {
      'taskSessionId': task.id,
      'startedAtEpochMs': task.startedAt.millisecondsSinceEpoch,
      'expectedEndAtEpochMs': task.expectedEndAt.millisecondsSinceEpoch,
      'guardConfigVersion': task.guardConfigVersion,
    });
    return _parseState(response);
  }

  @override
  Future<void> stop(String taskSessionId) async {
    if (taskSessionId.isEmpty) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.invalidData,
      );
    }
    await _invokeMap('stopTaskGuard', {'taskSessionId': taskSessionId});
  }

  @override
  Future<NativeTaskGuardState> getState() async {
    return _parseState(await _invokeMap('getTaskGuardState'));
  }

  @override
  Future<bool> acknowledge(String eventId) async {
    if (eventId.isEmpty) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.invalidData,
      );
    }
    final response = await _invokeMap('ackTaskEvent', {'eventId': eventId});
    final acknowledged = response['acknowledged'];
    if (acknowledged is! bool) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.invalidData,
      );
    }
    return acknowledged;
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      final response = await _methodChannel
          .invokeMethod<Object?>(method, {..._baseArguments, ...arguments})
          .timeout(_timeout);
      if (response is! Map<Object?, Object?> ||
          response['contractVersion'] != taskGuardContractVersion) {
        throw const NativeTaskGuardFailure(
          NativeTaskGuardFailureKind.channelContractMismatch,
        );
      }
      return response;
    } on NativeTaskGuardFailure {
      rethrow;
    } on TimeoutException {
      throw const NativeTaskGuardFailure(NativeTaskGuardFailureKind.timeout);
    } on MissingPluginException {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw NativeTaskGuardFailure(_failureKindForCode(error.code));
    } on Object {
      throw const NativeTaskGuardFailure(NativeTaskGuardFailureKind.unknown);
    }
  }

  NativeTaskGuardState _parseState(Map<Object?, Object?> response) {
    final taskSessionId = response['taskSessionId'];
    final isRunning = response['isRunning'];
    final hasPendingEvent = response['hasPendingEvent'] ?? false;
    if (taskSessionId is! String? ||
        isRunning is! bool ||
        hasPendingEvent is! bool ||
        (isRunning && taskSessionId == null)) {
      throw const NativeTaskGuardFailure(
        NativeTaskGuardFailureKind.invalidData,
      );
    }
    return NativeTaskGuardState(
      taskSessionId: taskSessionId,
      isRunning: isRunning,
      hasPendingEvent: hasPendingEvent,
    );
  }
}

NativeTaskEvent nativeTaskEventFromWire(Object? raw) {
  if (raw is! Map<Object?, Object?> ||
      raw.keys.toSet().difference(_eventKeys).isNotEmpty ||
      raw['contractVersion'] != taskGuardContractVersion) {
    throw const NativeTaskGuardFailure(
      NativeTaskGuardFailureKind.channelContractMismatch,
    );
  }
  final eventId = raw['eventId'];
  final taskSessionId = raw['taskSessionId'];
  final eventTypeValue = raw['eventType'];
  final occurredAtEpochMs = raw['occurredAtEpochMs'];
  final reasonValue = raw['reason'];
  final eventType = switch (eventTypeValue) {
    'taskFailed' => NativeTaskEventType.taskFailed,
    'deadlineReached' => NativeTaskEventType.deadlineReached,
    _ => null,
  };
  final reason = reasonValue is String
      ? TaskFailureReason.fromWireValue(reasonValue)
      : null;
  const nativeFailureReasons = {
    TaskFailureReason.foreignAppForeground,
    TaskFailureReason.monitorCapabilityLost,
    TaskFailureReason.recoveryDetectedViolation,
  };
  if (eventId is! String ||
      eventId.isEmpty ||
      eventId.length > 200 ||
      taskSessionId is! String ||
      taskSessionId.isEmpty ||
      eventType == null ||
      occurredAtEpochMs is! int ||
      reasonValue is! String? ||
      (reasonValue != null && reason == null) ||
      (reason != null && !nativeFailureReasons.contains(reason)) ||
      (eventType == NativeTaskEventType.taskFailed && reason == null) ||
      (eventType == NativeTaskEventType.deadlineReached &&
          reasonValue != null)) {
    throw const NativeTaskGuardFailure(NativeTaskGuardFailureKind.invalidData);
  }
  return NativeTaskEvent(
    eventId: eventId,
    taskSessionId: taskSessionId,
    type: eventType,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(
      occurredAtEpochMs,
      isUtc: true,
    ),
    failureReason: reason,
  );
}

const _eventKeys = {
  'contractVersion',
  'eventId',
  'taskSessionId',
  'eventType',
  'occurredAtEpochMs',
  'reason',
};

NativeTaskGuardFailureKind _failureKindForCode(String code) {
  return switch (code) {
    'channelContractMismatch' =>
      NativeTaskGuardFailureKind.channelContractMismatch,
    'notDeviceOwner' => NativeTaskGuardFailureKind.notDeviceOwner,
    'usageAccessMissing' => NativeTaskGuardFailureKind.usageAccessMissing,
    'notificationPermissionMissing' =>
      NativeTaskGuardFailureKind.notificationPermissionMissing,
    'foregroundServiceStartDenied' =>
      NativeTaskGuardFailureKind.foregroundServiceStartDenied,
    'nativeStateCorrupt' => NativeTaskGuardFailureKind.nativeStateCorrupt,
    'nativeUnavailable' => NativeTaskGuardFailureKind.nativeUnavailable,
    _ => NativeTaskGuardFailureKind.unknown,
  };
}
