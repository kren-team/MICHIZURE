import 'dart:async';

import 'package:michizure/features/group/domain/group.dart';
import 'package:michizure/features/group/domain/group_invite.dart';
import 'package:michizure/features/group/domain/group_member.dart';
import 'package:michizure/features/group/domain/group_repository.dart';

final class FakeGroupRepository implements GroupRepository {
  Object? createError;
  Object? joinError;
  Object? leaveError;
  Completer<void>? createCompleter;
  Completer<void>? joinCompleter;
  Stream<Group?> groupStream = Stream.value(null);
  Stream<List<GroupMember>> membersStream = Stream.value(const []);
  int createCalls = 0;
  int joinCalls = 0;
  int leaveCalls = 0;
  int transferCalls = 0;
  int createInviteCalls = 0;
  int revokeInviteCalls = 0;
  String? lastGroupName;
  String? lastInviteToken;

  @override
  Stream<Group?> watchGroup(String groupId) => groupStream;

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) => membersStream;

  @override
  Future<String> createGroup({
    required String userId,
    required String displayName,
    required String name,
  }) async {
    createCalls += 1;
    lastGroupName = name;
    if (createError case final error?) {
      throw error;
    }
    await createCompleter?.future;
    return 'group-1';
  }

  @override
  Future<void> joinGroup({
    required String userId,
    required String displayName,
    required String rawInviteToken,
  }) async {
    joinCalls += 1;
    lastInviteToken = rawInviteToken;
    if (joinError case final error?) {
      throw error;
    }
    await joinCompleter?.future;
  }

  @override
  Future<IssuedGroupInvite> createInvite({
    required String userId,
    required String groupId,
  }) async {
    createInviteCalls += 1;
    final now = DateTime.utc(2026);
    return IssuedGroupInvite(
      rawToken: 'raw-token',
      invite: GroupInvite(
        tokenHash: 'a' * 64,
        groupId: groupId,
        groupName: 'Group',
        createdByUid: userId,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        revokedAt: null,
      ),
    );
  }

  @override
  Future<void> revokeInvite({
    required String userId,
    required String tokenHash,
  }) async {
    revokeInviteCalls += 1;
  }

  @override
  Future<void> transferOwnership({
    required String userId,
    required String groupId,
    required String newOwnerUid,
  }) async {
    transferCalls += 1;
  }

  @override
  Future<void> leaveGroup({
    required String userId,
    required String groupId,
  }) async {
    leaveCalls += 1;
    if (leaveError case final error?) {
      throw error;
    }
  }
}
