import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/push_notifications.dart';

final class SharedPreferencesDeviceIdStore implements DeviceIdStore {
  static const _key = 'notification_device_id_v1';

  @override
  Future<String> getOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(_key, id);
    return id;
  }
}
