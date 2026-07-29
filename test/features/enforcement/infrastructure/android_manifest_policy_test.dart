import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release manifest keeps debug-only access out and declares Task Guard',
    () {
      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final debugManifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();

      expect(mainManifest, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(mainManifest, isNot(contains('usesCleartextTraffic')));
      expect(debugManifest, contains('QUERY_ALL_PACKAGES'));
      expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
      expect(mainManifest, contains('android.permission.FOREGROUND_SERVICE"'));
      expect(
        mainManifest,
        contains('android.permission.FOREGROUND_SERVICE_SYSTEM_EXEMPTED'),
      );
      expect(
        mainManifest,
        contains('android:name=".monitoring.TaskGuardService"'),
      );
      expect(
        mainManifest,
        contains('android:foregroundServiceType="systemExempted"'),
      );
      expect(mainManifest, contains('android:exported="false"'));
      expect(
        mainManifest,
        contains('android.permission.RECEIVE_BOOT_COMPLETED'),
      );
      expect(
        mainManifest,
        contains('android:name=".enforcement.LockReconcileReceiver"'),
      );
      expect(mainManifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(mainManifest, isNot(contains('AccessibilityService')));
    },
  );
}
