import 'device_capabilities.dart';
import 'lockable_app.dart';

abstract interface class DeviceControlRepository {
  Future<DeviceCapabilities> getCapabilities();

  Future<void> openUsageAccessSettings();

  Future<void> openNotificationSettings();

  Future<List<LockableApp>> listLockableApps();

  Future<Set<String>> getSelectedPackageNames();

  Future<Set<String>> saveSelectedPackageNames(Set<String> packageNames);
}
