import 'package:firebase_auth/firebase_auth.dart';

import '../domain/recovery.dart';

final class FirebaseRecoveryAuthGateway implements RecoveryAuthGateway {
  FirebaseRecoveryAuthGateway(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  @override
  Future<RecoveryAuthResult> recoverSession() async {
    final user = await _firebaseAuth.authStateChanges().first;
    if (user == null) {
      return const RecoveryAuthResult(status: RecoveryAuthStatus.signedOut);
    }
    try {
      final token = await user.getIdTokenResult(true);
      if (token.token == null || token.token!.isEmpty) {
        await _firebaseAuth.signOut();
        return const RecoveryAuthResult(
          status: RecoveryAuthStatus.invalidCredentialSignedOut,
        );
      }
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.authenticated,
        userId: user.uid,
      );
    } on FirebaseAuthException catch (error) {
      final disposition = classifyAuthRecoveryCode(error.code);
      if (disposition == RecoveryAuthErrorDisposition.signOut) {
        await _firebaseAuth.signOut();
        return const RecoveryAuthResult(
          status: RecoveryAuthStatus.invalidCredentialSignedOut,
        );
      }
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.temporarilyUnavailable,
        userId: user.uid,
      );
    } on Object {
      return RecoveryAuthResult(
        status: RecoveryAuthStatus.temporarilyUnavailable,
        userId: user.uid,
      );
    }
  }
}

enum RecoveryAuthErrorDisposition { signOut, keepSession }

RecoveryAuthErrorDisposition classifyAuthRecoveryCode(String code) {
  return switch (code) {
    'invalid-user-token' ||
    'invalid-refresh-token' ||
    'user-token-expired' ||
    'token-expired' ||
    'user-disabled' ||
    'user-not-found' => RecoveryAuthErrorDisposition.signOut,
    _ => RecoveryAuthErrorDisposition.keepSession,
  };
}
