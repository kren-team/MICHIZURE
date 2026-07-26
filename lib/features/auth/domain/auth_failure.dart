enum AuthFailureKind {
  invalidEmail,
  weakPassword,
  emailAlreadyInUse,
  invalidCredential,
  networkUnavailable,
  rateLimited,
  unknown,
}

final class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;

  @override
  String toString() => 'AuthFailure($kind)';
}
