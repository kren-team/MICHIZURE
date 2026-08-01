import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';
import 'package:michizure/features/notifications/infrastructure/firebase_push_messaging_gateway.dart';

void main() {
  test('FCM data is preserved for display and tap navigation', () {
    final message = pushNotificationMessageFromRemoteMessage(
      const RemoteMessage(
        messageId: 'message-1',
        notification: RemoteNotification(title: '通知', body: '本文'),
        data: {
          'eventType': 'contribution-created',
          'debtId': 'debt-1',
          'contributionId': 'contribution-1',
          'sourceId': 'contribution-1',
        },
      ),
    );

    expect(message?.eventType, PushNotificationEventType.contributionCreated);
    expect(message?.debtId, 'debt-1');
    expect(message?.contributionId, 'contribution-1');
    expect(message?.sourceId, 'contribution-1');
  });
}
