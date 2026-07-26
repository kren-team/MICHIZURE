sealed class BootstrapException implements Exception {
  const BootstrapException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class MissingLiveFirebaseConfiguration extends BootstrapException {
  const MissingLiveFirebaseConfiguration()
    : super(
        'Live Firebase configuration is required outside debug builds. '
        'Provide every MICHIZURE_FIREBASE_* dart-define.',
      );
}

final class FirebaseBootstrapException extends BootstrapException {
  const FirebaseBootstrapException(super.message, {required this.cause});

  final Object cause;
}
