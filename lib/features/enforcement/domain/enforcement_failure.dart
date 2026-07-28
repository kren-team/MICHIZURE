enum EnforcementFailureKind {
  channelContractMismatch,
  packageProtected,
  packageNotInstalled,
  nativeStateCorrupt,
  nativeUnavailable,
  timeout,
  invalidData,
  unsupportedPlatform,
  unknown,
}

final class EnforcementFailure implements Exception {
  const EnforcementFailure(this.kind);

  final EnforcementFailureKind kind;

  @override
  String toString() => 'EnforcementFailure($kind)';
}
