import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';

void main() {
  test('notification event types map to the expected debt routes', () {
    for (final eventType in [
      PushNotificationEventType.debtCreated,
      PushNotificationEventType.contributionCreated,
    ]) {
      expect(
        _message(eventType: eventType).navigationPath,
        '/debts/debt-1/repay',
      );
    }
    expect(
      _message(
        eventType: PushNotificationEventType.debtCompleted,
      ).navigationPath,
      '/debts/debt-1',
    );
  });

  test('missing or invalid debt identifiers are ignored safely', () {
    expect(
      _message(
        eventType: PushNotificationEventType.debtCreated,
        debtId: null,
      ).navigationPath,
      isNull,
    );
    expect(
      _message(
        eventType: PushNotificationEventType.debtCreated,
        debtId: 'invalid/id',
      ).navigationPath,
      isNull,
    );
    expect(
      _message(
        eventType: PushNotificationEventType.debtCreated,
        debtId: 'invalid?query',
      ).navigationPath,
      isNull,
    );
  });
}

PushNotificationMessage _message({
  required PushNotificationEventType eventType,
  String? debtId = 'debt-1',
}) {
  return PushNotificationMessage(
    title: '通知',
    body: '本文',
    eventType: eventType,
    debtId: debtId,
    sourceId: 'source-1',
  );
}
