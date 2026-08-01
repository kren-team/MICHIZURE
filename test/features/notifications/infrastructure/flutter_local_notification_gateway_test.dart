import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';
import 'package:michizure/features/notifications/infrastructure/flutter_local_notification_gateway.dart';

void main() {
  test('local notification payload preserves navigation data', () {
    const original = PushNotificationMessage(
      messageId: 'message-1',
      title: '救済が進みました',
      body: '本文',
      eventType: PushNotificationEventType.contributionCreated,
      debtId: 'debt-1',
      contributionId: 'contribution-1',
      sourceId: 'contribution-1',
    );

    final decoded = decodeNotificationPayload(
      encodeNotificationPayload(original),
    );

    expect(decoded?.messageId, original.messageId);
    expect(decoded?.eventType, original.eventType);
    expect(decoded?.debtId, original.debtId);
    expect(decoded?.contributionId, original.contributionId);
    expect(decoded?.sourceId, original.sourceId);
    expect(decoded?.navigationPath, '/debts/debt-1/repay');
  });
}
