import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/recovery.dart';

final class FirebaseRecoveryAuthGateway implements RecoveryAuthGateway {
  FirebaseRecoveryAuthGateway(this._client);

  final FirebaseAuthSessionClient _client;
  Future<RecoveryAuthResult>? _inFlight;

  @override
  Future<RecoveryAuthResult> recoverSession() {
    final current = _inFlight;
    if (current != null) {
      return current;
    }
    final future = _recoverSession();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<RecoveryAuthResult> _recoverSession() async {
    final userId = _client.currentUserId;
    if (userId == null) {
      return const RecoveryAuthResult(status: RecoveryAuthStatus.signedOut);
    }
    try {
      final token = await _client.forceRefreshIdToken();
      if (token == null || token.isEmpty) {
        await _client.signOut();
        return const RecoveryAuthResult(
          status: RecoveryAuthStatus.invalidCredentialSignedOut,
        );
      }
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.authenticated,
        userId: userId,
      );
    } on FirebaseException catch (error) {
      final disposition = classifyAuthRecoveryError(error);
      if (kDebugMode) {
        debugPrint(
          'Auth token validation failed: '
          'type=${error.runtimeType} plugin=${error.plugin} code=${error.code} '
          'disposition=$disposition',
        );
      }
      if (disposition == RecoveryAuthErrorDisposition.signOut) {
        await _client.signOut();
        return const RecoveryAuthResult(
          status: RecoveryAuthStatus.invalidCredentialSignedOut,
        );
      }
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.temporarilyUnavailable,
        userId: userId,
      );
    } on Object {
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.temporarilyUnavailable,
        userId: userId,
      );
    }
  }
}

abstract interface class FirebaseAuthSessionClient {
  String? get currentUserId;

  Future<String?> forceRefreshIdToken();

  Future<void> signOut();
}

final class FlutterFireAuthSessionClient implements FirebaseAuthSessionClient {
  FlutterFireAuthSessionClient(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  @override
  String? get currentUserId => _firebaseAuth.currentUser?.uid;

  @override
  Future<String?> forceRefreshIdToken() async {
    return (await _firebaseAuth.currentUser?.getIdTokenResult(true))?.token;
  }

  @override
  Future<void> signOut() => _firebaseAuth.signOut();
}

enum RecoveryAuthErrorDisposition { signOut, keepSession }

RecoveryAuthErrorDisposition classifyAuthRecoveryCode(String code) {
  final normalizedCode = code
      .trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .replaceFirst(RegExp(r'^error-'), '');
  return switch (normalizedCode) {
    'invalid-user-token' ||
    'invalid-refresh-token' ||
    'user-token-expired' ||
    'token-expired' ||
    'user-disabled' ||
    'user-not-found' => RecoveryAuthErrorDisposition.signOut,
    _ => RecoveryAuthErrorDisposition.keepSession,
  };
}

RecoveryAuthErrorDisposition classifyAuthRecoveryError(
  FirebaseException error,
) {
  final codeDisposition = classifyAuthRecoveryCode(error.code);
  if (codeDisposition == RecoveryAuthErrorDisposition.signOut) {
    return codeDisposition;
  }

  // firebase_auth Android 6.5.6 maps the native emulator response to
  // code=unknown and preserves only this protocol marker in message.
  // Keep this fallback exact and scoped to firebase_auth; do not classify
  // arbitrary exception text as a permanent credential failure.
  if (error.plugin == 'firebase_auth' &&
      error.code.trim().toLowerCase() == 'unknown' &&
      _hasInvalidRefreshTokenProtocolMarker(error.message)) {
    return RecoveryAuthErrorDisposition.signOut;
  }
  return RecoveryAuthErrorDisposition.keepSession;
}

bool _hasInvalidRefreshTokenProtocolMarker(String? message) {
  if (message == null) {
    return false;
  }
  final normalizedMessage = message.trim();
  final bracketedMarker = _firebaseProtocolMarker
      .allMatches(message)
      .any((match) => match.group(1) == 'INVALID_REFRESH_TOKEN');
  if (bracketedMarker) {
    return true;
  }

  // firebase_auth_platform_interface 9.0.5 removes a trailing " ]" while
  // parsing Android messages, so the same marker can arrive without its
  // closing bracket. Accept only the complete truncated marker shape.
  return _truncatedFirebaseProtocolMarker
          .firstMatch(normalizedMessage)
          ?.group(1) ==
      'INVALID_REFRESH_TOKEN';
}

final RegExp _firebaseProtocolMarker = RegExp(r'\[\s*([A-Z][A-Z0-9_]*)\s*\]');
final RegExp _truncatedFirebaseProtocolMarker = RegExp(
  r'^(?:An internal error has occurred\.\s*)?'
  r'\[\s*([A-Z][A-Z0-9_]*)\s*$',
);
