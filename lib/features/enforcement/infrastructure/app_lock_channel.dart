import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/app_lock.dart';
import '../domain/app_lock_repository.dart';
import '../domain/enforcement_failure.dart';
import 'device_control_channel.dart';

final class MethodChannelAppLockRepository implements AppLockRepository {
  MethodChannelAppLockRepository({MethodChannel? channel, Duration? timeout})
    : _channel = channel ?? const MethodChannel(deviceControlChannelName),
      _timeout = timeout ?? const Duration(seconds: 5);

  final MethodChannel _channel;
  final Duration _timeout;

  static const _baseArguments = <String, Object?>{
    'contractVersion': deviceControlContractVersion,
  };

  @override
  Future<AppLockState> applyObligation(LockObligationRequest request) {
    if (request.debtId.isEmpty ||
        request.taskSessionId.isEmpty ||
        request.expiresAt.isBefore(request.createdAt)) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return _invoke(
      'applyLockObligation',
      arguments: {
        'debtId': request.debtId,
        'taskSessionId': request.taskSessionId,
        'createdAtEpochMs': request.createdAt.millisecondsSinceEpoch,
        'expiresAtEpochMs': request.expiresAt.millisecondsSinceEpoch,
      },
    );
  }

  @override
  Future<AppLockState> getState() => _invoke('getLockState');

  @override
  Future<AppLockState> reconcile() => _invoke('reconcileLocks');

  @override
  Future<AppLockState> releaseObligation({
    required String debtId,
    required LockRemoteStatus resolution,
  }) {
    if (debtId.isEmpty || resolution == LockRemoteStatus.active) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return _invoke(
      'releaseLockObligation',
      arguments: {'debtId': debtId, 'resolution': resolution.wireValue},
    );
  }

  Future<AppLockState> _invoke(
    String method, {
    Map<String, Object?> arguments = const {},
  }) async {
    try {
      final response = await _channel
          .invokeMethod<Object?>(method, {..._baseArguments, ...arguments})
          .timeout(_timeout);
      if (response is! Map<Object?, Object?> ||
          response['contractVersion'] != deviceControlContractVersion) {
        throw const EnforcementFailure(
          EnforcementFailureKind.channelContractMismatch,
        );
      }
      return _parseState(response);
    } on EnforcementFailure {
      rethrow;
    } on TimeoutException {
      throw const EnforcementFailure(EnforcementFailureKind.timeout);
    } on MissingPluginException {
      throw const EnforcementFailure(
        EnforcementFailureKind.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw EnforcementFailure(_lockFailureKindForCode(error.code));
    } on Object {
      throw const EnforcementFailure(EnforcementFailureKind.unknown);
    }
  }

  AppLockState _parseState(Map<Object?, Object?> value) {
    const keys = {
      'contractVersion',
      'obligations',
      'effectiveTargetCount',
      'ownedSuspensionCount',
      'appliedCount',
      'releasedCount',
      'failedCount',
      'nextDeadlineEpochMs',
    };
    if (value.keys.toSet().difference(keys).isNotEmpty) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    final rawObligations = value['obligations'];
    final effectiveTargetCount = value['effectiveTargetCount'];
    final ownedSuspensionCount = value['ownedSuspensionCount'];
    final appliedCount = value['appliedCount'];
    final releasedCount = value['releasedCount'];
    final failedCount = value['failedCount'];
    final nextDeadlineEpochMs = value['nextDeadlineEpochMs'];
    if (rawObligations is! List ||
        effectiveTargetCount is! int ||
        effectiveTargetCount < 0 ||
        ownedSuspensionCount is! int ||
        ownedSuspensionCount < 0 ||
        appliedCount is! int ||
        appliedCount < 0 ||
        releasedCount is! int ||
        releasedCount < 0 ||
        failedCount is! int ||
        failedCount < 0 ||
        (nextDeadlineEpochMs is int && nextDeadlineEpochMs < 0) ||
        nextDeadlineEpochMs is! int?) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return AppLockState(
      obligations: rawObligations.map(_parseObligation).toList(growable: false),
      effectiveTargetCount: effectiveTargetCount,
      ownedSuspensionCount: ownedSuspensionCount,
      appliedCount: appliedCount,
      releasedCount: releasedCount,
      failedCount: failedCount,
      nextDeadline: nextDeadlineEpochMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              nextDeadlineEpochMs,
              isUtc: true,
            ),
    );
  }

  LockObligationSummary _parseObligation(Object? value) {
    const keys = {
      'debtId',
      'taskSessionId',
      'expiresAtEpochMs',
      'remoteStatus',
      'localState',
      'targetCount',
      'enforcedCount',
      'failedCount',
      'errorCode',
    };
    if (value is! Map<Object?, Object?> ||
        value.keys.toSet().difference(keys).isNotEmpty) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    final debtId = value['debtId'];
    final taskSessionId = value['taskSessionId'];
    final expiresAt = value['expiresAtEpochMs'];
    final remoteStatus = _enumByWire(
      LockRemoteStatus.values,
      value['remoteStatus'],
      (item) => item.wireValue,
    );
    final localState = _enumByWire(
      LockLocalState.values,
      value['localState'],
      (item) => item.wireValue,
    );
    final targetCount = value['targetCount'];
    final enforcedCount = value['enforcedCount'];
    final failedCount = value['failedCount'];
    final errorCode = value['errorCode'];
    if (debtId is! String ||
        debtId.isEmpty ||
        taskSessionId is! String ||
        taskSessionId.isEmpty ||
        expiresAt is! int ||
        remoteStatus == null ||
        localState == null ||
        targetCount is! int ||
        targetCount <= 0 ||
        enforcedCount is! int ||
        enforcedCount < 0 ||
        enforcedCount > targetCount ||
        failedCount is! int ||
        failedCount < 0 ||
        failedCount > targetCount ||
        errorCode is! String? ||
        (errorCode != null && !_lockErrorCodes.contains(errorCode))) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return LockObligationSummary(
      debtId: debtId,
      taskSessionId: taskSessionId,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      remoteStatus: remoteStatus,
      localState: localState,
      targetCount: targetCount,
      enforcedCount: enforcedCount,
      failedCount: failedCount,
      errorCode: errorCode,
    );
  }
}

const _lockErrorCodes = {
  'notDeviceOwner',
  'packageNotInstalled',
  'suspensionPartialFailure',
  'unsuspensionPartialFailure',
  'taskSnapshotMissing',
  'nativeStateCorrupt',
};

T? _enumByWire<T>(List<T> values, Object? raw, String Function(T) wireValue) {
  if (raw is! String) {
    return null;
  }
  return values.where((value) => wireValue(value) == raw).firstOrNull;
}

EnforcementFailureKind _lockFailureKindForCode(String code) {
  return switch (code) {
    'channelContractMismatch' => EnforcementFailureKind.channelContractMismatch,
    'notDeviceOwner' => EnforcementFailureKind.notDeviceOwner,
    'packageNotInstalled' => EnforcementFailureKind.packageNotInstalled,
    'suspensionPartialFailure' =>
      EnforcementFailureKind.suspensionPartialFailure,
    'unsuspensionPartialFailure' =>
      EnforcementFailureKind.unsuspensionPartialFailure,
    'taskSnapshotMissing' => EnforcementFailureKind.taskSnapshotMissing,
    'nativeStateCorrupt' => EnforcementFailureKind.nativeStateCorrupt,
    _ => EnforcementFailureKind.unknown,
  };
}
