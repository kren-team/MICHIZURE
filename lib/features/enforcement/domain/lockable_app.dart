enum PackageProtectionReason {
  self,
  deviceAdmin,
  launcher,
  dialer,
  permissionController,
  settings,
  packageManager,
}

final class LockableApp {
  const LockableApp({
    required this.packageName,
    required this.label,
    required this.isSelectable,
    required this.protectionReason,
  });

  final String packageName;
  final String label;
  final bool isSelectable;
  final PackageProtectionReason? protectionReason;
}
