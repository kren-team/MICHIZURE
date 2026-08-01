import '../domain/push_notifications.dart';

final class NotificationNavigationCoordinator {
  PushNotificationMessage? _pendingMessage;
  final Set<String> _handledKeys = {};

  void enqueue(PushNotificationMessage message) {
    final key = message.deduplicationKey;
    if (message.navigationPath == null ||
        key == null ||
        _handledKeys.contains(key)) {
      return;
    }
    _pendingMessage = message;
  }

  String? takeNextPath({required bool canNavigate}) {
    if (!canNavigate) {
      return null;
    }
    final message = _pendingMessage;
    final key = message?.deduplicationKey;
    final path = message?.navigationPath;
    if (message == null || key == null || path == null) {
      return null;
    }
    _pendingMessage = null;
    if (!_handledKeys.add(key)) {
      return null;
    }
    return path;
  }
}
