import 'package:flutter_test/flutter_test.dart';
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
}
