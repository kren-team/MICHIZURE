enum GroupFailureKind {
  invalidName,
  alreadyMember,
  invalidInvite,
  inviteExpired,
  inviteRevoked,
  groupFull,
  notMember,
  ownerMustTransfer,
  invalidTransferTarget,
  rulesDenied,
  offline,
  conflict,
  invalidData,
  unknown,
}

final class GroupFailure implements Exception {
  const GroupFailure(this.kind);

  final GroupFailureKind kind;

  @override
  String toString() => 'GroupFailure($kind)';
}
