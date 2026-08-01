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
      expect(debugManifest, isNot(contains('QUERY_ALL_PACKAGES')));
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

  test('release uses one bundled MediaPipe Lite model without ML Kit', () {
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final taskModels = Directory('android/app/src/main/assets')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.task'))
        .toList();
    final router = File('lib/app/router.dart').readAsStringSync();
    final home = File(
      'lib/features/group/presentation/group_home_screen.dart',
    ).readAsStringSync();
    final debugFixture = File(
      'android/app/src/debug/assets/pose_fixture_generated.png',
    );
    final mainFixture = File(
      'android/app/src/main/assets/pose_fixture_generated.png',
    );
    final debugFixtureRunner = File(
      'android/app/src/debug/kotlin/com/kren/michizure/pose/'
      'GeneratedPoseFixtureDiagnostics.kt',
    );

    expect(appBuild, contains('com.google.mediapipe:tasks-vision:1.0.0'));
    expect(appBuild, isNot(contains('pose-detection')));
    expect(appBuild, isNot(contains('com.google.mlkit')));
    expect(pubspec, isNot(contains('google_mlkit')));
    expect(taskModels, hasLength(1));
    expect(taskModels.single.path, endsWith('pose_landmarker_lite.task'));
    expect(taskModels.single.lengthSync(), 5777746);
    expect(debugFixture.existsSync(), isTrue);
    expect(mainFixture.existsSync(), isFalse);
    expect(debugFixtureRunner.existsSync(), isTrue);
    expect(router, contains('if (kDebugMode)'));
    expect(
      router,
      contains(
        'path: debugSquatLabRoutePath,\n'
        '          builder: (context, state) => const SquatLabScreen()',
      ),
    );
    expect(home, contains('if (kDebugMode)\n      IconButton('));
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
