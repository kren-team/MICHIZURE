import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/recovery/domain/recovery.dart';
import 'package:michizure/features/recovery/infrastructure/firebase_recovery_auth_gateway.dart';

void main() {
  test('permanent credential codes require a safe sign out', () {
    for (final code in [
      'invalid-user-token',
      'invalid-refresh-token',
      'user-token-expired',
      'token-expired',
      'user-disabled',
      'user-not-found',
    ]) {
      expect(
        classifyAuthRecoveryCode(code),
        RecoveryAuthErrorDisposition.signOut,
        reason: code,
      );
    }
  });

  test('temporary and unknown errors preserve the current session', () {
    for (final code in [
      'network-request-failed',
      'too-many-requests',
      'internal-error',
      'unknown',
    ]) {
      expect(
        classifyAuthRecoveryCode(code),
        RecoveryAuthErrorDisposition.keepSession,
        reason: code,
      );
    }
  });

  test('valid current user and token remain authenticated', () async {
    final client = _FakeFirebaseAuthSessionClient(
      currentUserId: 'alice',
      token: 'valid-token',
    );
    final gateway = FirebaseRecoveryAuthGateway(client);

    final result = await gateway.recoverSession();

    expect(result.status, RecoveryAuthStatus.authenticated);
    expect(result.userId, 'alice');
    expect(client.refreshCalls, 1);
    expect(client.signOutCalls, 0);
  });

  test('temporary network failure does not sign out', () async {
    final client = _FakeFirebaseAuthSessionClient(
      currentUserId: 'alice',
      error: FirebaseException(
        plugin: 'firebase_auth',
        code: 'network-request-failed',
      ),
    );
    final gateway = FirebaseRecoveryAuthGateway(client);

    final result = await gateway.recoverSession();

    expect(result.status, RecoveryAuthStatus.temporarilyUnavailable);
    expect(result.userId, 'alice');
    expect(client.signOutCalls, 0);
  });

  test('typed permanent credential failure signs out', () async {
    final client = _FakeFirebaseAuthSessionClient(
      currentUserId: 'alice',
      error: FirebaseException(
        plugin: 'firebase_auth',
        code: 'invalid-refresh-token',
      ),
    );
    final gateway = FirebaseRecoveryAuthGateway(client);

    final result = await gateway.recoverSession();

    expect(result.status, RecoveryAuthStatus.invalidCredentialSignedOut);
    expect(client.signOutCalls, 1);
  });

  test(
    'Android unknown-code INVALID_REFRESH_TOKEN fallback signs out',
    () async {
      final error = FirebaseException(
        plugin: 'firebase_auth',
        code: 'unknown',
        message:
            'An internal error has occurred. '
            '[ INVALID_REFRESH_TOKEN ] while refreshing.',
      );
      final client = _FakeFirebaseAuthSessionClient(
        currentUserId: 'alice',
        error: error,
      );
      final gateway = FirebaseRecoveryAuthGateway(client);

      expect(
        classifyAuthRecoveryError(error),
        RecoveryAuthErrorDisposition.signOut,
      );
      final result = await gateway.recoverSession();

      expect(result.status, RecoveryAuthStatus.invalidCredentialSignedOut);
      expect(client.signOutCalls, 1);
    },
  );

  test('FlutterFire truncated INVALID_REFRESH_TOKEN fallback signs out', () {
    for (final message in [
      '[ INVALID_REFRESH_TOKEN',
      'An internal error has occurred. [ INVALID_REFRESH_TOKEN',
    ]) {
      expect(
        classifyAuthRecoveryError(
          FirebaseException(
            plugin: 'firebase_auth',
            code: 'unknown',
            message: message,
          ),
        ),
        RecoveryAuthErrorDisposition.signOut,
        reason: message,
      );
    }
  });

  test('unknown unrelated Firebase Auth message preserves session', () {
    expect(
      classifyAuthRecoveryError(
        FirebaseException(
          plugin: 'firebase_auth',
          code: 'unknown',
          message: 'An unrelated SDK failure.',
        ),
      ),
      RecoveryAuthErrorDisposition.keepSession,
    );
    expect(
      classifyAuthRecoveryError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unknown',
          message: '[ INVALID_REFRESH_TOKEN ]',
        ),
      ),
      RecoveryAuthErrorDisposition.keepSession,
    );
  });

  test('concurrent validation calls share one token refresh', () async {
    final blocker = Completer<void>();
    final client = _FakeFirebaseAuthSessionClient(
      currentUserId: 'alice',
      token: 'valid-token',
      blocker: blocker,
    );
    final gateway = FirebaseRecoveryAuthGateway(client);

    final first = gateway.recoverSession();
    final second = gateway.recoverSession();
    await Future<void>.delayed(Duration.zero);

    expect(client.refreshCalls, 1);
    blocker.complete();
    expect(identical(await first, await second), isTrue);
  });
}

final class _FakeFirebaseAuthSessionClient
    implements FirebaseAuthSessionClient {
  _FakeFirebaseAuthSessionClient({
    required this.currentUserId,
    this.token,
    this.error,
    this.blocker,
  });

  @override
  final String? currentUserId;
  final String? token;
  final Object? error;
  final Completer<void>? blocker;
  int refreshCalls = 0;
  int signOutCalls = 0;

  @override
  Future<String?> forceRefreshIdToken() async {
    refreshCalls += 1;
    await blocker?.future;
    if (error case final error?) {
      throw error;
    }
    return token;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
}
