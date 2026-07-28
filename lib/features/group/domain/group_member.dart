enum GroupMemberRole { owner, member }

final class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    required this.updatedAt,
  });

  static const int schemaVersion = 1;

  final String userId;
  final String displayName;
  final GroupMemberRole role;
  final DateTime joinedAt;
  final DateTime updatedAt;
}
