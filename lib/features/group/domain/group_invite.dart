final class GroupInvite {
  const GroupInvite({
    required this.tokenHash,
    required this.groupId,
    required this.groupName,
    required this.createdByUid,
    required this.createdAt,
    required this.expiresAt,
    required this.revokedAt,
  });

  static const int schemaVersion = 1;

  final String tokenHash;
  final String groupId;
  final String groupName;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
}

final class IssuedGroupInvite {
  const IssuedGroupInvite({required this.rawToken, required this.invite});

  final String rawToken;
  final GroupInvite invite;
}

final class GeneratedInviteToken {
  const GeneratedInviteToken({required this.rawToken, required this.hash});

  final String rawToken;
  final String hash;
}

abstract interface class InviteTokenGenerator {
  GeneratedInviteToken generate();

  String hash(String rawToken);
}
