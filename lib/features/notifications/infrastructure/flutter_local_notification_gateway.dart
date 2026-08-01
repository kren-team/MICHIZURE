import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/push_notifications.dart';

const notificationChannelId = 'michizure_alerts_v1';
const notificationChannelName = 'MICHIZUREの通知';
const notificationChannelDescription = '負債の発生・返済・完済を通知します';
const michizureNotificationChannel = AndroidNotificationChannel(
  notificationChannelId,
  notificationChannelName,
  description: notificationChannelDescription,
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

final defaultLocalNotificationGateway = FlutterLocalNotificationGateway(
  FlutterLocalNotificationsPlugin(),
);

final class FlutterLocalNotificationGateway
    implements LocalNotificationGateway {
  FlutterLocalNotificationGateway(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<PushNotificationMessage> _openedMessages =
      StreamController.broadcast();
  Future<void>? _initialization;

  @override
  Stream<PushNotificationMessage> get openedMessages => _openedMessages.stream;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final message = decodeNotificationPayload(response.payload);
        if (message != null) {
          _openedMessages.add(message);
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(michizureNotificationChannel);
  }

  @override
  Future<void> show(PushNotificationMessage message) async {
    await initialize();
    final key = message.deduplicationKey;
    if (key == null) {
      return;
    }
    await _plugin.show(
      id: _notificationId(key),
      title: message.title,
      body: message.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          notificationChannelName,
          channelDescription: notificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          channelShowBadge: true,
        ),
      ),
      payload: encodeNotificationPayload(message),
    );
  }

  @override
  Future<PushNotificationMessage?> getInitialMessage() async {
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) {
      return null;
    }
    return decodeNotificationPayload(details?.notificationResponse?.payload);
  }
}

String encodeNotificationPayload(PushNotificationMessage message) {
  return jsonEncode({
    'messageId': message.messageId,
    'title': message.title,
    'body': message.body,
    'eventType': message.eventType?.wireValue,
    'debtId': message.debtId,
    'contributionId': message.contributionId,
    'sourceId': message.sourceId,
  });
}

PushNotificationMessage? decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) {
    return null;
  }
  try {
    final value = jsonDecode(payload);
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final title = value['title'];
    final body = value['body'];
    if (title is! String || title.isEmpty || body is! String || body.isEmpty) {
      return null;
    }
    return PushNotificationMessage(
      messageId: value['messageId'] as String?,
      title: title,
      body: body,
      eventType: PushNotificationEventType.fromWireValue(
        value['eventType'] as String?,
      ),
      debtId: value['debtId'] as String?,
      contributionId: value['contributionId'] as String?,
      sourceId: value['sourceId'] as String?,
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

int _notificationId(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}
