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

final class PushNotificationMessage {
  const PushNotificationMessage({required this.title, required this.body});

  final String title;
  final String body;
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
