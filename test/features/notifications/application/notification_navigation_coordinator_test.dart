import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/notifications/application/notification_navigation_coordinator.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';

void main() {
  test('holds a terminated notification until navigation is ready', () {
    final coordinator = NotificationNavigationCoordinator();
    coordinator.enqueue(_message());

    expect(coordinator.takeNextPath(canNavigate: false), isNull);
    expect(coordinator.takeNextPath(canNavigate: true), '/debts/debt-1/repay');
  });

  test('handles the same event only once', () {
    final coordinator = NotificationNavigationCoordinator();
    coordinator.enqueue(_message());
    expect(coordinator.takeNextPath(canNavigate: true), isNotNull);

    coordinator.enqueue(_message());
    expect(coordinator.takeNextPath(canNavigate: true), isNull);
  });
}

PushNotificationMessage _message() {
  return const PushNotificationMessage(
    messageId: 'message-1',
    title: '通知',
    body: '本文',
    eventType: PushNotificationEventType.debtCreated,
    debtId: 'debt-1',
    sourceId: 'debt-1',
  );
}
