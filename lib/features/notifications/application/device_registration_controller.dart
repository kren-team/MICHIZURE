import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/domain/auth_user.dart';
import '../domain/push_notifications.dart';

final deviceRegistrationControllerProvider =
    NotifierProvider<DeviceRegistrationController, DeviceRegistrationState>(
      DeviceRegistrationController.new,
    );

final class DeviceRegistrationState {
  const DeviceRegistrationState({
    this.foregroundMessage,
    this.messageSequence = 0,
  });

  final PushNotificationMessage? foregroundMessage;
  final int messageSequence;
}

final class DeviceRegistrationController
    extends Notifier<DeviceRegistrationState> {
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<PushNotificationMessage>? _messageSubscription;
  StreamSubscription<PushNotificationMessage>? _openedMessageSubscription;
  String? _registeredUserId;
  String? _deviceId;
  int _generation = 0;

  @override
  DeviceRegistrationState build() {
    ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (_, next) {
      _onAuthChanged(next.value);
    }, fireImmediately: true);
    ref.onDispose(() {
      _generation += 1;
      unawaited(_tokenSubscription?.cancel());
      unawaited(_messageSubscription?.cancel());
      unawaited(_openedMessageSubscription?.cancel());
    });
    return const DeviceRegistrationState();
  }

  Future<void> unregisterCurrentDevice() async {
    final userId = _registeredUserId;
    final deviceId = _deviceId;
    _generation += 1;
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _openedMessageSubscription?.cancel();
    _openedMessageSubscription = null;
    if (userId == null) {
      return;
    }
    if (deviceId != null) {
      try {
        await ref
            .read(deviceRegistrationRepositoryProvider)
            .delete(userId: userId, deviceId: deviceId);
      } on Object {
        // Logout remains available even when remote device cleanup fails.
      }
    }
    try {
      await ref.read(pushMessagingGatewayProvider).deleteToken();
    } on Object {
      // The Firestore registration is authoritative for notification delivery.
    }
    _registeredUserId = null;
  }

  void _onAuthChanged(AuthUser? user) {
    final userId = user?.id;
    if (userId == _registeredUserId) {
      return;
    }
    _generation += 1;
    unawaited(_tokenSubscription?.cancel());
    _tokenSubscription = null;
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    unawaited(_openedMessageSubscription?.cancel());
    _openedMessageSubscription = null;
    _registeredUserId = userId;
    if (userId != null) {
      unawaited(_register(userId, _generation));
    }
  }

  Future<void> _register(String userId, int generation) async {
    final messaging = ref.read(pushMessagingGatewayProvider);
    try {
      final permitted = await messaging.requestPermission();
      if (!permitted || !_isCurrent(userId, generation)) {
        return;
      }
      final deviceId = await ref.read(deviceIdStoreProvider).getOrCreate();
      final token = await messaging.getToken();
      if (token == null || token.isEmpty || !_isCurrent(userId, generation)) {
        return;
      }
      _deviceId = deviceId;
      await _upsert(userId: userId, deviceId: deviceId, token: token);
      if (!_isCurrent(userId, generation)) {
        return;
      }
      _tokenSubscription = messaging.tokenRefreshes.listen((token) {
        if (token.isNotEmpty && _isCurrent(userId, generation)) {
          unawaited(_upsert(userId: userId, deviceId: deviceId, token: token));
        }
      });
      _messageSubscription ??= messaging.foregroundMessages.listen(
        _showForegroundMessage,
      );
      _openedMessageSubscription ??= messaging.openedMessages.listen(
        _showForegroundMessage,
      );
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && _isCurrent(userId, generation)) {
        _showForegroundMessage(initialMessage);
      }
    } on Object {
      // Push registration is optional and must not block the signed-in app.
    }
  }

  Future<void> _upsert({
    required String userId,
    required String deviceId,
    required String token,
  }) async {
    try {
      await ref
          .read(deviceRegistrationRepositoryProvider)
          .upsert(
            DeviceRegistration(
              userId: userId,
              deviceId: deviceId,
              token: token,
            ),
          );
    } on Object {
      // Token refresh will provide another best-effort registration attempt.
    }
  }

  bool _isCurrent(String userId, int generation) =>
      ref.mounted && _registeredUserId == userId && _generation == generation;

  void _showForegroundMessage(PushNotificationMessage message) {
    if (!ref.mounted) {
      return;
    }
    state = DeviceRegistrationState(
      foregroundMessage: message,
      messageSequence: state.messageSequence + 1,
    );
  }
}
