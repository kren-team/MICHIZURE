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
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(id: 'alice')),
          ),
          deviceRegistrationRepositoryProvider.overrideWithValue(registrations),
          deviceIdStoreProvider.overrideWithValue(_FakeDeviceIdStore()),
          pushMessagingGatewayProvider.overrideWithValue(messaging),
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
        const PushNotificationMessage(title: '通知', body: '本文'),
      );
      await _flush();
      expect(registrations.upserts.last.token, 'token-2');
      expect(
        container
            .read(deviceRegistrationControllerProvider)
            .foregroundMessage
            ?.title,
        '通知',
      );

      await container
          .read(deviceRegistrationControllerProvider.notifier)
          .unregisterCurrentDevice();
      expect(registrations.deleted, [('alice', 'device-0123456789')]);
      expect(messaging.deleteTokenCalls, 1);
    },
  );
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
  int deleteTokenCalls = 0;

  @override
  Stream<PushNotificationMessage> get foregroundMessages =>
      messageController.stream;

  @override
  Stream<PushNotificationMessage> get openedMessages => const Stream.empty();

  @override
  Stream<String> get tokenRefreshes => tokenController.stream;

  @override
  Future<void> deleteToken() async {
    deleteTokenCalls += 1;
  }

  @override
  Future<PushNotificationMessage?> getInitialMessage() async => null;

  @override
  Future<String?> getToken() async => 'token-1';

  @override
  Future<bool> requestPermission() async => true;
}
