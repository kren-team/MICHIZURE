import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/device_capabilities.dart';
import '../domain/device_control_repository.dart';
import '../domain/enforcement_failure.dart';
import '../domain/lockable_app.dart';

const String deviceControlChannelName = 'com.kren.michizure/device_control/v1';
const int deviceControlContractVersion = 1;

final class MethodChannelDeviceControlRepository
    implements DeviceControlRepository {
  MethodChannelDeviceControlRepository({
    MethodChannel? channel,
    Duration? timeout,
  }) : _channel = channel ?? const MethodChannel(deviceControlChannelName),
       _timeout = timeout ?? const Duration(seconds: 5);

  final MethodChannel _channel;
  final Duration _timeout;

  static const _baseArguments = <String, Object?>{
    'contractVersion': deviceControlContractVersion,
  };

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    final payload = await _invokeMap('getCapabilities');
    return DeviceCapabilities(
      isDeviceOwner: _requiredBool(payload, 'isDeviceOwner'),
      hasUsageAccess: _requiredBool(payload, 'hasUsageAccess'),
      hasNotificationPermission: _requiredBool(
        payload,
        'hasNotificationPermission',
      ),
      packageVisibility: _requiredBool(payload, 'hasBroadPackageVisibility')
          ? PackageVisibility.broad
          : PackageVisibility.scoped,
      isUserUnlocked: _requiredBool(payload, 'isUserUnlocked'),
      supportsHardEnforcement: _requiredBool(
        payload,
        'supportsHardEnforcement',
      ),
      sdkInt: _requiredInt(payload, 'sdkInt'),
    );
  }

  @override
  Future<void> openUsageAccessSettings() async {
    await _invokeMap('openUsageAccessSettings');
  }

  @override
  Future<void> openNotificationSettings() async {
    await _invokeMap('openNotificationSettings');
  }

  @override
  Future<List<LockableApp>> listLockableApps() async {
    final payload = await _invokeMap('listLockableApps');
    final rawApps = payload['apps'];
    if (rawApps is! List) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return rawApps.map(_parseApp).toList(growable: false);
  }

  @override
  Future<Set<String>> getSelectedPackageNames() async {
    final payload = await _invokeMap('getSelectedPackages');
    return _parsePackageNames(payload);
  }

  @override
  Future<Set<String>> saveSelectedPackageNames(Set<String> packageNames) async {
    final payload = await _invokeMap('saveSelectedPackages', <String, Object?>{
      'packageNames': packageNames.toList()..sort(),
    });
    return _parsePackageNames(payload);
  }

  Future<Map<Object?, Object?>> _invokeMap(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
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
      return response;
    } on EnforcementFailure {
      rethrow;
    } on TimeoutException {
      throw const EnforcementFailure(EnforcementFailureKind.timeout);
    } on MissingPluginException {
      throw const EnforcementFailure(
        EnforcementFailureKind.unsupportedPlatform,
      );
    } on PlatformException catch (error) {
      throw EnforcementFailure(_failureKindForCode(error.code));
    } on Object {
      throw const EnforcementFailure(EnforcementFailureKind.unknown);
    }
  }

  LockableApp _parseApp(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    final packageName = value['packageName'];
    final label = value['label'];
    final isSelectable = value['isSelectable'];
    final reason = value['protectionReason'];
    if (packageName is! String ||
        packageName.isEmpty ||
        label is! String ||
        label.isEmpty ||
        isSelectable is! bool ||
        reason is! String? ||
        (isSelectable && reason != null)) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    final protectionReason = reason == null
        ? null
        : PackageProtectionReason.values
              .where((value) => value.name == reason)
              .firstOrNull;
    if (reason != null && protectionReason == null) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return LockableApp(
      packageName: packageName,
      label: label,
      isSelectable: isSelectable,
      protectionReason: protectionReason,
    );
  }

  Set<String> _parsePackageNames(Map<Object?, Object?> payload) {
    final rawPackages = payload['packageNames'];
    if (rawPackages is! List ||
        rawPackages.any((value) => value is! String || value.isEmpty)) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return rawPackages.cast<String>().toSet();
  }

  bool _requiredBool(Map<Object?, Object?> payload, String key) {
    final value = payload[key];
    if (value is! bool) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return value;
  }

  int _requiredInt(Map<Object?, Object?> payload, String key) {
    final value = payload[key];
    if (value is! int) {
      throw const EnforcementFailure(EnforcementFailureKind.invalidData);
    }
    return value;
  }
}

EnforcementFailureKind _failureKindForCode(String code) {
  return switch (code) {
    'channelContractMismatch' => EnforcementFailureKind.channelContractMismatch,
    'packageProtected' => EnforcementFailureKind.packageProtected,
    'packageNotInstalled' => EnforcementFailureKind.packageNotInstalled,
    'nativeStateCorrupt' => EnforcementFailureKind.nativeStateCorrupt,
    'nativeUnavailable' => EnforcementFailureKind.nativeUnavailable,
    _ => EnforcementFailureKind.unknown,
  };
}
