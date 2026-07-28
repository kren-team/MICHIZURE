import 'group.dart';
import 'group_invite.dart';
import 'group_member.dart';

abstract interface class GroupRepository {
  Stream<Group?> watchGroup(String groupId);

  Stream<List<GroupMember>> watchMembers(String groupId);

  Future<String> createGroup({
    required String userId,
    required String displayName,
    required String name,
  });

  Future<void> joinGroup({
    required String userId,
    required String displayName,
    required String rawInviteToken,
  });

  Future<IssuedGroupInvite> createInvite({
    required String userId,
    required String groupId,
  });

  Future<void> revokeInvite({
    required String userId,
    required String tokenHash,
  });

  Future<void> transferOwnership({
    required String userId,
    required String groupId,
    required String newOwnerUid,
  });

  Future<void> leaveGroup({required String userId, required String groupId});
}
