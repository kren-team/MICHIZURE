enum PackageVisibility { broad, scoped }

final class DeviceCapabilities {
  const DeviceCapabilities({
    required this.isDeviceOwner,
    required this.hasUsageAccess,
    required this.hasNotificationPermission,
    required this.packageVisibility,
    required this.isUserUnlocked,
    required this.supportsHardEnforcement,
    required this.sdkInt,
  });

  final bool isDeviceOwner;
  final bool hasUsageAccess;
  final bool hasNotificationPermission;
  final PackageVisibility packageVisibility;
  final bool isUserUnlocked;
  final bool supportsHardEnforcement;
  final int sdkInt;

  bool get isManagedDemoReady =>
      isDeviceOwner &&
      hasUsageAccess &&
      hasNotificationPermission &&
      isUserUnlocked &&
      supportsHardEnforcement;
}
