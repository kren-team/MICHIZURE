enum ProfileFailureKind { invalidDisplayName, invalidData, unknown }

final class ProfileFailure implements Exception {
  const ProfileFailure(this.kind);

  final ProfileFailureKind kind;
}
