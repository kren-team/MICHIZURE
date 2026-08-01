import 'package:firebase_messaging/firebase_messaging.dart';

import '../domain/push_notifications.dart';

final class FirebasePushMessagingGateway implements PushMessagingGateway {
  FirebasePushMessagingGateway(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushNotificationMessage> get foregroundMessages => FirebaseMessaging
      .onMessage
      .map(pushNotificationMessageFromRemoteMessage)
      .where((message) => message != null)
      .cast<PushNotificationMessage>();

  @override
  Stream<PushNotificationMessage> get openedMessages => FirebaseMessaging
      .onMessageOpenedApp
      .map(pushNotificationMessageFromRemoteMessage)
      .where((message) => message != null)
      .cast<PushNotificationMessage>();

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Future<PushNotificationMessage?> getInitialMessage() async {
    return pushNotificationMessageFromRemoteMessage(
      await _messaging.getInitialMessage(),
    );
  }
}

PushNotificationMessage? pushNotificationMessageFromRemoteMessage(
  RemoteMessage? message,
) {
  final notification = message?.notification;
  final title = notification?.title;
  final body = notification?.body;
  if (title == null || title.isEmpty || body == null || body.isEmpty) {
    return null;
  }
  final data = message?.data ?? const <String, dynamic>{};
  return PushNotificationMessage(
    messageId: message?.messageId,
    title: title,
    body: body,
    eventType: PushNotificationEventType.fromWireValue(
      _stringValue(data['eventType']),
    ),
    debtId: _stringValue(data['debtId']),
    contributionId: _stringValue(data['contributionId']),
    sourceId: _stringValue(data['sourceId']),
  );
}

String? _stringValue(Object? value) => value is String ? value : null;
