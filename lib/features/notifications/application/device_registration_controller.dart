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
    this.navigationMessage,
    this.navigationSequence = 0,
  });

  final PushNotificationMessage? navigationMessage;
  final int navigationSequence;
}

final class DeviceRegistrationController
    extends Notifier<DeviceRegistrationState> {
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<PushNotificationMessage>? _messageSubscription;
  StreamSubscription<PushNotificationMessage>? _openedMessageSubscription;
  StreamSubscription<PushNotificationMessage>? _localOpenedSubscription;
  final Set<String> _displayedMessageKeys = {};
  final Set<String> _openedMessageKeys = {};
  String? _registeredUserId;
  String? _deviceId;
  bool _notificationsPermitted = false;
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
      unawaited(_localOpenedSubscription?.cancel());
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
    await _localOpenedSubscription?.cancel();
    _localOpenedSubscription = null;
    _notificationsPermitted = false;
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
    unawaited(_localOpenedSubscription?.cancel());
    _localOpenedSubscription = null;
    _displayedMessageKeys.clear();
    _openedMessageKeys.clear();
    _notificationsPermitted = false;
    _registeredUserId = userId;
    if (userId != null) {
      unawaited(_register(userId, _generation));
    }
  }

  Future<void> _register(String userId, int generation) async {
    final messaging = ref.read(pushMessagingGatewayProvider);
    final localNotifications = ref.read(localNotificationGatewayProvider);
    try {
      await localNotifications.initialize();
      if (!_isCurrent(userId, generation)) {
        return;
      }
      _messageSubscription ??= messaging.foregroundMessages.listen(
        (message) => unawaited(_showForegroundNotification(message)),
      );
      _openedMessageSubscription ??= messaging.openedMessages.listen(
        _queueNavigation,
      );
      _localOpenedSubscription ??= localNotifications.openedMessages.listen(
        _queueNavigation,
      );
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && _isCurrent(userId, generation)) {
        _queueNavigation(initialMessage);
      }
      final initialLocalMessage = await localNotifications.getInitialMessage();
      if (initialLocalMessage != null && _isCurrent(userId, generation)) {
        _queueNavigation(initialLocalMessage);
      }
      final permitted = await messaging.requestPermission();
      if (!permitted || !_isCurrent(userId, generation)) {
        return;
      }
      _notificationsPermitted = true;
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

  Future<void> _showForegroundNotification(
    PushNotificationMessage message,
  ) async {
    final key = message.deduplicationKey;
    if (!ref.mounted ||
        !_notificationsPermitted ||
        key == null ||
        !_displayedMessageKeys.add(key)) {
      return;
    }
    try {
      await ref.read(localNotificationGatewayProvider).show(message);
    } on Object {
      _displayedMessageKeys.remove(key);
    }
  }

  void _queueNavigation(PushNotificationMessage message) {
    final key = message.deduplicationKey;
    if (!ref.mounted ||
        message.navigationPath == null ||
        key == null ||
        !_openedMessageKeys.add(key)) {
      return;
    }
    state = DeviceRegistrationState(
      navigationMessage: message,
      navigationSequence: state.navigationSequence + 1,
    );
  }
}
