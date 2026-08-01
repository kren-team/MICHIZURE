import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

final class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  @override
  Stream<AuthUser?> authStateChanges() =>
      _firebaseAuth.authStateChanges().map(_toAuthUser);

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw mapFirebaseAuthException(error);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw mapFirebaseAuthException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (error) {
      throw mapFirebaseAuthException(error);
    }
  }

  static AuthUser? _toAuthUser(User? user) {
    if (user == null) {
      return null;
    }

    return AuthUser(id: user.uid);
  }
}

AuthFailure mapFirebaseAuthException(FirebaseAuthException error) {
  final kind = switch (error.code) {
    'invalid-email' => AuthFailureKind.invalidEmail,
    'weak-password' => AuthFailureKind.weakPassword,
    'email-already-in-use' => AuthFailureKind.emailAlreadyInUse,
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'wrong-password' ||
    'user-not-found' => AuthFailureKind.invalidCredential,
    'network-request-failed' => AuthFailureKind.networkUnavailable,
    'too-many-requests' => AuthFailureKind.rateLimited,
    _ => AuthFailureKind.unknown,
  };

  return AuthFailure(kind);
}
