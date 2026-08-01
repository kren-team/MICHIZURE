import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/infrastructure/flutter_local_notification_gateway.dart';

void main() {
  test('Android manifest and notification API use the app channel ID', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final backend = File(
      'services/notification_api/notification_api/firebase_backend.py',
    ).readAsStringSync();
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(manifest, contains(notificationChannelId));
    expect(
      backend,
      contains(
        'ANDROID_NOTIFICATION_CHANNEL_ID = '
        '"$notificationChannelId"',
      ),
    );
    expect(michizureNotificationChannel.importance, Importance.high);
    expect(michizureNotificationChannel.playSound, isTrue);
    expect(michizureNotificationChannel.enableVibration, isTrue);
    expect(michizureNotificationChannel.showBadge, isTrue);
    expect(app, isNot(contains('showSnackBar')));
  });
}
