final class DeviceRegistration {
  const DeviceRegistration({
    required this.userId,
    required this.deviceId,
    required this.token,
  });

  final String userId;
  final String deviceId;
  final String token;
}

abstract interface class DeviceRegistrationRepository {
  Future<void> upsert(DeviceRegistration registration);

  Future<void> delete({required String userId, required String deviceId});
}

abstract interface class DeviceIdStore {
  Future<String> getOrCreate();
}

enum PushNotificationEventType {
  debtCreated('debt-created'),
  contributionCreated('contribution-created'),
  debtCompleted('debt-completed');

  const PushNotificationEventType(this.wireValue);

  final String wireValue;

  static PushNotificationEventType? fromWireValue(String? value) {
    for (final type in values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}

final class PushNotificationMessage {
  const PushNotificationMessage({
    required this.title,
    required this.body,
    this.messageId,
    this.eventType,
    this.debtId,
    this.contributionId,
    this.sourceId,
  });

  static final RegExp _documentId = RegExp(r'^[A-Za-z0-9_-]{1,150}$');
  static final RegExp _sourceId = RegExp(r'^[^/]{1,240}$');

  final String title;
  final String body;
  final String? messageId;
  final PushNotificationEventType? eventType;
  final String? debtId;
  final String? contributionId;
  final String? sourceId;

  String? get navigationPath {
    final id = debtId;
    final type = eventType;
    if (id == null || !_documentId.hasMatch(id) || type == null) {
      return null;
    }
    return switch (type) {
      PushNotificationEventType.debtCreated ||
      PushNotificationEventType.contributionCreated => '/debts/$id/repay',
      PushNotificationEventType.debtCompleted => '/debts/$id',
    };
  }

  String? get deduplicationKey {
    final type = eventType;
    final source = sourceId;
    if (type != null && source != null && _sourceId.hasMatch(source)) {
      return 'event:${type.wireValue}:$source';
    }
    final id = messageId;
    if (id != null && id.isNotEmpty) {
      return 'message:$id';
    }
    return null;
  }
}

abstract interface class LocalNotificationGateway {
  Stream<PushNotificationMessage> get openedMessages;

  Future<void> initialize();

  Future<void> show(PushNotificationMessage message);

  Future<PushNotificationMessage?> getInitialMessage();
}

abstract interface class PushMessagingGateway {
  Stream<String> get tokenRefreshes;

  Stream<PushNotificationMessage> get foregroundMessages;

  Stream<PushNotificationMessage> get openedMessages;

  Future<bool> requestPermission();

  Future<String?> getToken();

  Future<void> deleteToken();

  Future<PushNotificationMessage?> getInitialMessage();
}

abstract interface class NotificationEventPublisher {
  Future<void> debtCreated(String debtId);

  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  });

  Future<void> debtCompleted(String debtId);
}
