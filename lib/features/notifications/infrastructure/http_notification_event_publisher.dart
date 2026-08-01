import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../domain/push_notifications.dart';

final class HttpNotificationEventPublisher
    implements NotificationEventPublisher {
  HttpNotificationEventPublisher({required this._auth, required String baseUrl})
    : _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final FirebaseAuth _auth;
  final String _baseUrl;

  @override
  Future<void> debtCreated(String debtId) {
    return _post('/v1/notifications/debt-created', {'debtId': debtId});
  }

  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) {
    return _post('/v1/notifications/contribution-created', {
      'debtId': debtId,
      'contributionId': contributionId,
    });
  }

  @override
  Future<void> debtCompleted(String debtId) {
    return _post('/v1/notifications/debt-completed', {'debtId': debtId});
  }

  Future<void> _post(String path, Map<String, String> payload) async {
    if (_baseUrl.isEmpty) {
      return;
    }
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty) {
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse('$_baseUrl$path'));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('notification API status ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }
}

final class BestEffortNotificationEventPublisher
    implements NotificationEventPublisher {
  BestEffortNotificationEventPublisher(this._delegate);

  final NotificationEventPublisher _delegate;

  @override
  Future<void> debtCreated(String debtId) =>
      _run(event: 'debt-created', action: () => _delegate.debtCreated(debtId));

  @override
  Future<void> contributionCreated({
    required String debtId,
    required String contributionId,
  }) => _run(
    event: 'contribution-created',
    action: () => _delegate.contributionCreated(
      debtId: debtId,
      contributionId: contributionId,
    ),
  );

  @override
  Future<void> debtCompleted(String debtId) => _run(
    event: 'debt-completed',
    action: () => _delegate.debtCompleted(debtId),
  );

  Future<void> _run({
    required String event,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
    } on Object {
      developer.log('notification delivery failed: $event', name: 'MICHIZURE');
    }
  }
}
