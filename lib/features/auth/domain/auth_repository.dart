import 'auth_user.dart';

abstract interface class AuthRepository {
  Stream<AuthUser?> authStateChanges();

  Future<void> register({required String email, required String password});

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}
