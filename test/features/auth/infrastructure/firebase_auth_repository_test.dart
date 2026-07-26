import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/auth/domain/auth_failure.dart';
import 'package:michizure/features/auth/infrastructure/firebase_auth_repository.dart';

void main() {
  group('mapFirebaseAuthException', () {
    for (final testCase in <({String code, AuthFailureKind expected})>[
      (code: 'invalid-email', expected: AuthFailureKind.invalidEmail),
      (code: 'weak-password', expected: AuthFailureKind.weakPassword),
      (
        code: 'email-already-in-use',
        expected: AuthFailureKind.emailAlreadyInUse,
      ),
      (code: 'wrong-password', expected: AuthFailureKind.invalidCredential),
      (
        code: 'network-request-failed',
        expected: AuthFailureKind.networkUnavailable,
      ),
      (code: 'too-many-requests', expected: AuthFailureKind.rateLimited),
      (code: 'unexpected-code', expected: AuthFailureKind.unknown),
    ]) {
      test('maps ${testCase.code} without exposing an SDK message', () {
        final failure = mapFirebaseAuthException(
          FirebaseAuthException(
            code: testCase.code,
            message: 'Do not expose this Firebase SDK message.',
          ),
        );

        expect(failure.kind, testCase.expected);
        expect(failure.toString(), 'AuthFailure(${testCase.expected})');
      });
    }
  });
}
