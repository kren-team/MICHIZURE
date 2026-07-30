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

  test('production source contains no synthetic pose implementation', () {
    final productionRoot = Directory('android/app/src/main');
    final productionText = productionRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path;
          return path.endsWith('.kt') ||
              path.endsWith('.java') ||
              path.endsWith('.xml');
        })
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(productionText, isNot(contains('FakeSquatDetector')));
    expect(productionText, isNot(contains('fake_debug')));
    expect(productionText, isNot(contains('syntheticPose')));
  });

  test('demo target is isolated and requests no permission', () {
    final targetManifest = File(
      'tools/demo-target/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final targetBuild = File(
      'tools/demo-target/app/build.gradle.kts',
    ).readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();

    expect(targetManifest, contains('android:name=".MainActivity"'));
    expect(
      targetBuild,
      contains('applicationId = "com.kren.michizure.demotarget"'),
    );
    expect(targetManifest, isNot(contains('uses-permission')));
    expect(appBuild, isNot(contains('demo-target')));
    expect(appBuild, isNot(contains('demotarget')));
  });
}
