import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/notifications/application/device_registration_controller.dart';
import 'package:michizure/features/notifications/domain/push_notifications.dart';

void main() {
  test(
    'registers, refreshes, receives, and removes the current device',
    () async {
      final registrations = _FakeRegistrationRepository();
      final messaging = _FakeMessagingGateway();
      final localNotifications = _FakeLocalNotificationGateway();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(id: 'alice')),
          ),
          deviceRegistrationRepositoryProvider.overrideWithValue(registrations),
          deviceIdStoreProvider.overrideWithValue(_FakeDeviceIdStore()),
          pushMessagingGatewayProvider.overrideWithValue(messaging),
          localNotificationGatewayProvider.overrideWithValue(
            localNotifications,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        deviceRegistrationControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );

      await _flush();
      expect(registrations.upserts.single.token, 'token-1');

      messaging.tokenController.add('token-2');
      messaging.messageController.add(
        const PushNotificationMessage(
          messageId: 'message-1',
          title: '通知',
          body: '本文',
          eventType: PushNotificationEventType.debtCreated,
          debtId: 'debt-1',
          sourceId: 'debt-1',
        ),
      );
      messaging.messageController.add(
        const PushNotificationMessage(
          messageId: 'message-1',
          title: '通知',
          body: '本文',
          eventType: PushNotificationEventType.debtCreated,
          debtId: 'debt-1',
          sourceId: 'debt-1',
        ),
      );
      await _flush();
      expect(registrations.upserts.last.token, 'token-2');
      expect(localNotifications.shown, hasLength(1));
      expect(
        container.read(deviceRegistrationControllerProvider).navigationMessage,
        isNull,
      );

      messaging.openedController.add(
        const PushNotificationMessage(
          messageId: 'message-1',
          title: '通知',
          body: '本文',
          eventType: PushNotificationEventType.debtCreated,
          debtId: 'debt-1',
          sourceId: 'debt-1',
        ),
      );
      await _flush();
      expect(
        container
            .read(deviceRegistrationControllerProvider)
            .navigationMessage
            ?.navigationPath,
        '/debts/debt-1/repay',
      );
      expect(localNotifications.shown, hasLength(1));

      await container
          .read(deviceRegistrationControllerProvider.notifier)
          .unregisterCurrentDevice();
      expect(registrations.deleted, [('alice', 'device-0123456789')]);
      expect(messaging.deleteTokenCalls, 1);
    },
  );

  test('queues terminated and foreground notification taps once', () async {
    final messaging = _FakeMessagingGateway()
      ..initialMessage = const PushNotificationMessage(
        messageId: 'message-initial',
        title: '完済',
        body: '本文',
        eventType: PushNotificationEventType.debtCompleted,
        debtId: 'debt-1',
        sourceId: 'debt-1',
      );
    final localNotifications = _FakeLocalNotificationGateway();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'alice')),
        ),
        deviceRegistrationRepositoryProvider.overrideWithValue(
          _FakeRegistrationRepository(),
        ),
        deviceIdStoreProvider.overrideWithValue(_FakeDeviceIdStore()),
        pushMessagingGatewayProvider.overrideWithValue(messaging),
        localNotificationGatewayProvider.overrideWithValue(localNotifications),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      deviceRegistrationControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );

    await _flush();
    expect(
      container
          .read(deviceRegistrationControllerProvider)
          .navigationMessage
          ?.navigationPath,
      '/debts/debt-1',
    );
    expect(
      container.read(deviceRegistrationControllerProvider).navigationSequence,
      1,
    );

    localNotifications.openedController.add(
      const PushNotificationMessage(
        messageId: 'message-local',
        title: '救済',
        body: '本文',
        eventType: PushNotificationEventType.contributionCreated,
        debtId: 'debt-2',
        contributionId: 'contribution-2',
        sourceId: 'contribution-2',
      ),
    );
    await _flush();
    expect(
      container
          .read(deviceRegistrationControllerProvider)
          .navigationMessage
          ?.navigationPath,
      '/debts/debt-2/repay',
    );
    expect(
      container.read(deviceRegistrationControllerProvider).navigationSequence,
      2,
    );
  });

  test('does not show a foreground notification without permission', () async {
    final messaging = _FakeMessagingGateway()..permissionGranted = false;
    final localNotifications = _FakeLocalNotificationGateway();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'alice')),
        ),
        deviceRegistrationRepositoryProvider.overrideWithValue(
          _FakeRegistrationRepository(),
        ),
        deviceIdStoreProvider.overrideWithValue(_FakeDeviceIdStore()),
        pushMessagingGatewayProvider.overrideWithValue(messaging),
        localNotificationGatewayProvider.overrideWithValue(localNotifications),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      deviceRegistrationControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await _flush();

    messaging.messageController.add(
      const PushNotificationMessage(
        messageId: 'message-denied',
        title: '通知',
        body: '本文',
        eventType: PushNotificationEventType.debtCreated,
        debtId: 'debt-1',
        sourceId: 'debt-1',
      ),
    );
    await _flush();

    expect(localNotifications.shown, isEmpty);
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeRegistrationRepository
    implements DeviceRegistrationRepository {
  final List<DeviceRegistration> upserts = [];
  final List<(String, String)> deleted = [];

  @override
  Future<void> upsert(DeviceRegistration registration) async {
    upserts.add(registration);
  }

  @override
  Future<void> delete({
    required String userId,
    required String deviceId,
  }) async {
    deleted.add((userId, deviceId));
  }
}

final class _FakeDeviceIdStore implements DeviceIdStore {
  @override
  Future<String> getOrCreate() async => 'device-0123456789';
}

final class _FakeMessagingGateway implements PushMessagingGateway {
  final tokenController = StreamController<String>.broadcast();
  final messageController =
      StreamController<PushNotificationMessage>.broadcast();
  final openedController =
      StreamController<PushNotificationMessage>.broadcast();
  PushNotificationMessage? initialMessage;
  bool permissionGranted = true;
  int deleteTokenCalls = 0;

  @override
  Stream<PushNotificationMessage> get foregroundMessages =>
      messageController.stream;

  @override
  Stream<PushNotificationMessage> get openedMessages => openedController.stream;

  @override
  Stream<String> get tokenRefreshes => tokenController.stream;

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls += 1;
  }

  @override
  Future<PushNotificationMessage?> getInitialMessage() async => initialMessage;

  @override
  Future<String?> getToken() async => 'token-1';

  @override
  Future<bool> requestPermission() async => permissionGranted;
}

final class _FakeLocalNotificationGateway implements LocalNotificationGateway {
  final openedController =
      StreamController<PushNotificationMessage>.broadcast();
  final List<PushNotificationMessage> shown = [];

  @override
  Stream<PushNotificationMessage> get openedMessages => openedController.stream;

  @override
  Future<PushNotificationMessage?> getInitialMessage() async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(PushNotificationMessage message) async {
    shown.add(message);
  }
}
