enum DebtFailureKind {
  invalidData,
  notFound,
  rulesDenied,
  offline,
  conflict,
  nativeReleaseFailed,
  unknown,
}

final class DebtFailure implements Exception {
  const DebtFailure(this.kind);

  final DebtFailureKind kind;
}
