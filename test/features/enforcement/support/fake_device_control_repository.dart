import 'dart:async';

import 'package:michizure/features/enforcement/domain/device_capabilities.dart';
import 'package:michizure/features/enforcement/domain/device_control_repository.dart';
import 'package:michizure/features/enforcement/domain/lockable_app.dart';

final class FakeDeviceControlRepository implements DeviceControlRepository {
  DeviceCapabilities capabilities = readyCapabilities;
  List<LockableApp> apps = testApps;
  Set<String> selectedPackageNames = {};

  Object? loadError;
  Object? saveError;
  Completer<Set<String>>? saveCompleter;

  int capabilityCalls = 0;
  int listCalls = 0;
  int readSelectionCalls = 0;
  int saveCalls = 0;
  int openUsageCalls = 0;
  int openNotificationCalls = 0;

  @override
  Future<DeviceCapabilities> getCapabilities() async {
    capabilityCalls += 1;
    if (loadError case final error?) {
      throw error;
    }
    return capabilities;
  }

  @override
  Future<List<LockableApp>> listLockableApps() async {
    listCalls += 1;
    if (loadError case final error?) {
      throw error;
    }
    return apps;
  }

  @override
  Future<Set<String>> getSelectedPackageNames() async {
    readSelectionCalls += 1;
    if (loadError case final error?) {
      throw error;
    }
    return selectedPackageNames.toSet();
  }

  @override
  Future<Set<String>> saveSelectedPackageNames(Set<String> packageNames) async {
    saveCalls += 1;
    if (saveError case final error?) {
      throw error;
    }
    final completer = saveCompleter;
    if (completer != null) {
      final saved = await completer.future;
      selectedPackageNames = saved.toSet();
      return saved.toSet();
    }
    selectedPackageNames = packageNames.toSet();
    return selectedPackageNames.toSet();
  }

  @override
  Future<void> openNotificationSettings() async {
    openNotificationCalls += 1;
  }

  @override
  Future<void> openUsageAccessSettings() async {
    openUsageCalls += 1;
  }
}

const readyCapabilities = DeviceCapabilities(
  isDeviceOwner: true,
  hasUsageAccess: true,
  hasNotificationPermission: true,
  packageVisibility: PackageVisibility.broad,
  isUserUnlocked: true,
  supportsHardEnforcement: true,
  sdkInt: 36,
);

const testApps = [
  LockableApp(
    packageName: 'social.app',
    label: 'Social',
    isSelectable: true,
    protectionReason: null,
  ),
  LockableApp(
    packageName: 'video.app',
    label: 'Video',
    isSelectable: true,
    protectionReason: null,
  ),
  LockableApp(
    packageName: 'com.kren.michizure',
    label: 'MICHIZURE',
    isSelectable: false,
    protectionReason: PackageProtectionReason.self,
  ),
];
