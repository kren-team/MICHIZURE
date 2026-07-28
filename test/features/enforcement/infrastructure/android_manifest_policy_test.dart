import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('broad package visibility and cleartext are debug-only', () {
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
  });
}
