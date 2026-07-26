import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/time/clock.dart';
import '../../profile/domain/user_profile.dart';
import '../domain/group.dart';
import '../domain/group_failure.dart';
import '../domain/group_invite.dart';
import '../domain/group_member.dart';
import '../domain/group_repository.dart';

final class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository(
    this._firestore,
    this._inviteTokenGenerator, [
    this._clock = const SystemClock(),
  ]);

  static const Duration inviteLifetime = Duration(hours: 24);

  final FirebaseFirestore _firestore;
  final InviteTokenGenerator _inviteTokenGenerator;
  final Clock _clock;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('groupInvites');

  @override
  Stream<Group?> watchGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return groupFromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) {
    return _groups
        .doc(groupId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) =>
                    groupMemberFromFirestore(document.id, document.data()),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<String> createGroup({
    required String userId,
    required String displayName,
    required String name,
  }) async {
    final normalizedName = GroupNameValidator.normalize(name);
    if (!GroupNameValidator.isValid(normalizedName)) {
      throw const GroupFailure(GroupFailureKind.invalidName);
    }
    final normalizedDisplayName = _validatedDisplayName(displayName);
    final groupReference = _groups.doc();
    final userReference = _users.doc(userId);
    final memberReference = groupReference.collection('members').doc(userId);

    try {
      await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userReference);
        if (!userSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.invalidData);
        }
        if (userSnapshot.data()!['groupId'] != null) {
          throw const GroupFailure(GroupFailureKind.alreadyMember);
        }

        transaction.set(groupReference, {
          'name': normalizedName,
          'ownerUid': userId,
          'memberCount': 1,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'schemaVersion': Group.schemaVersion,
        });
        transaction.set(memberReference, {
          'userId': userId,
          'displayNameSnapshot': normalizedDisplayName,
          'role': 'owner',
          'inviteTokenHash': null,
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'schemaVersion': GroupMember.schemaVersion,
        });
        transaction.update(userReference, {
          'groupId': groupReference.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return groupReference.id;
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> joinGroup({
    required String userId,
    required String displayName,
    required String rawInviteToken,
  }) async {
    final normalizedToken = rawInviteToken.trim();
    if (normalizedToken.isEmpty) {
      throw const GroupFailure(GroupFailureKind.invalidInvite);
    }
    final normalizedDisplayName = _validatedDisplayName(displayName);
    final tokenHash = _inviteTokenGenerator.hash(normalizedToken);
    final inviteReference = _invites.doc(tokenHash);
    final userReference = _users.doc(userId);

    try {
      await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userReference);
        final inviteSnapshot = await transaction.get(inviteReference);
        if (!userSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.invalidData);
        }
        if (userSnapshot.data()!['groupId'] != null) {
          throw const GroupFailure(GroupFailureKind.alreadyMember);
        }
        if (!inviteSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.invalidInvite);
        }

        final invite = groupInviteFromFirestore(
          inviteSnapshot.id,
          inviteSnapshot.data()!,
        );
        if (invite.revokedAt != null) {
          throw const GroupFailure(GroupFailureKind.inviteRevoked);
        }
        if (!_clock.now().isBefore(invite.expiresAt)) {
          throw const GroupFailure(GroupFailureKind.inviteExpired);
        }

        final groupReference = _groups.doc(invite.groupId);
        final memberReference = groupReference
            .collection('members')
            .doc(userId);
        final groupSnapshot = await transaction.get(groupReference);
        final memberSnapshot = await transaction.get(memberReference);
        if (!groupSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.invalidInvite);
        }
        if (memberSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.alreadyMember);
        }

        final group = groupFromFirestore(
          groupSnapshot.id,
          groupSnapshot.data()!,
        );
        if (group.memberCount >= Group.maximumMemberCount) {
          throw const GroupFailure(GroupFailureKind.groupFull);
        }

        transaction.set(memberReference, {
          'userId': userId,
          'displayNameSnapshot': normalizedDisplayName,
          'role': 'member',
          'inviteTokenHash': tokenHash,
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'schemaVersion': GroupMember.schemaVersion,
        });
        transaction.update(groupReference, {
          'memberCount': group.memberCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(userReference, {
          'groupId': group.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<IssuedGroupInvite> createInvite({
    required String userId,
    required String groupId,
  }) async {
    final generatedToken = _inviteTokenGenerator.generate();
    final inviteReference = _invites.doc(generatedToken.hash);
    final groupReference = _groups.doc(groupId);
    final memberReference = groupReference.collection('members').doc(userId);
    final expiresAt = _clock.now().toUtc().add(inviteLifetime);
    late Group group;

    try {
      await _firestore.runTransaction((transaction) async {
        final groupSnapshot = await transaction.get(groupReference);
        final memberSnapshot = await transaction.get(memberReference);
        final inviteSnapshot = await transaction.get(inviteReference);
        if (!groupSnapshot.exists || !memberSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.notMember);
        }
        if (inviteSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.conflict);
        }
        group = groupFromFirestore(groupSnapshot.id, groupSnapshot.data()!);

        transaction.set(inviteReference, {
          'groupId': groupId,
          'groupNameSnapshot': group.name,
          'createdByUid': userId,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'revokedAt': null,
          'schemaVersion': GroupInvite.schemaVersion,
        });
      });

      return IssuedGroupInvite(
        rawToken: generatedToken.rawToken,
        invite: GroupInvite(
          tokenHash: generatedToken.hash,
          groupId: groupId,
          groupName: group.name,
          createdByUid: userId,
          createdAt: _clock.now().toUtc(),
          expiresAt: expiresAt,
          revokedAt: null,
        ),
      );
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> revokeInvite({
    required String userId,
    required String tokenHash,
  }) async {
    try {
      await _invites.doc(tokenHash).update({
        'revokedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> transferOwnership({
    required String userId,
    required String groupId,
    required String newOwnerUid,
  }) async {
    if (userId == newOwnerUid) {
      throw const GroupFailure(GroupFailureKind.invalidTransferTarget);
    }
    final groupReference = _groups.doc(groupId);
    final oldOwnerReference = groupReference.collection('members').doc(userId);
    final newOwnerReference = groupReference
        .collection('members')
        .doc(newOwnerUid);

    try {
      await _firestore.runTransaction((transaction) async {
        final groupSnapshot = await transaction.get(groupReference);
        final oldOwnerSnapshot = await transaction.get(oldOwnerReference);
        final newOwnerSnapshot = await transaction.get(newOwnerReference);
        if (!groupSnapshot.exists ||
            !oldOwnerSnapshot.exists ||
            !newOwnerSnapshot.exists) {
          throw const GroupFailure(GroupFailureKind.invalidTransferTarget);
        }
        final group = groupFromFirestore(
          groupSnapshot.id,
          groupSnapshot.data()!,
        );
        if (group.ownerUid != userId ||
            oldOwnerSnapshot.data()!['role'] != 'owner' ||
            newOwnerSnapshot.data()!['role'] != 'member') {
          throw const GroupFailure(GroupFailureKind.invalidTransferTarget);
        }

        transaction.update(groupReference, {
          'ownerUid': newOwnerUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(oldOwnerReference, {
          'role': 'member',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(newOwnerReference, {
          'role': 'owner',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> leaveGroup({
    required String userId,
    required String groupId,
  }) async {
    final userReference = _users.doc(userId);
    final groupReference = _groups.doc(groupId);
    final memberReference = groupReference.collection('members').doc(userId);

    try {
      await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userReference);
        final groupSnapshot = await transaction.get(groupReference);
        final memberSnapshot = await transaction.get(memberReference);
        if (!userSnapshot.exists ||
            !groupSnapshot.exists ||
            !memberSnapshot.exists ||
            userSnapshot.data()!['groupId'] != groupId) {
          throw const GroupFailure(GroupFailureKind.notMember);
        }
        final group = groupFromFirestore(
          groupSnapshot.id,
          groupSnapshot.data()!,
        );
        if (group.ownerUid == userId ||
            memberSnapshot.data()!['role'] == 'owner') {
          throw const GroupFailure(GroupFailureKind.ownerMustTransfer);
        }

        transaction.delete(memberReference);
        transaction.update(groupReference, {
          'memberCount': group.memberCount - 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(userReference, {
          'groupId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on Object catch (error) {
      throw _mapFailure(error);
    }
  }

  String _validatedDisplayName(String value) {
    final normalized = ProfileValidator.normalizeDisplayName(value);
    if (!ProfileValidator.isValidDisplayName(normalized)) {
      throw const GroupFailure(GroupFailureKind.invalidData);
    }
    return normalized;
  }
}

Group groupFromFirestore(String id, Map<String, dynamic> data) {
  final name = data['name'];
  final ownerUid = data['ownerUid'];
  final memberCount = data['memberCount'];
  final createdAt = data['createdAt'];
  final updatedAt = data['updatedAt'];
  if (name is! String ||
      !GroupNameValidator.isValid(name) ||
      GroupNameValidator.normalize(name) != name ||
      ownerUid is! String ||
      ownerUid.isEmpty ||
      memberCount is! int ||
      memberCount < 1 ||
      memberCount > Group.maximumMemberCount ||
      createdAt is! Timestamp ||
      updatedAt is! Timestamp ||
      data['schemaVersion'] != Group.schemaVersion) {
    throw const GroupFailure(GroupFailureKind.invalidData);
  }
  return Group(
    id: id,
    name: name,
    ownerUid: ownerUid,
    memberCount: memberCount,
    createdAt: createdAt.toDate(),
    updatedAt: updatedAt.toDate(),
  );
}

GroupMember groupMemberFromFirestore(String id, Map<String, dynamic> data) {
  final userId = data['userId'];
  final displayName = data['displayNameSnapshot'];
  final role = data['role'];
  final joinedAt = data['joinedAt'];
  final updatedAt = data['updatedAt'];
  if (userId != id ||
      displayName is! String ||
      !ProfileValidator.isValidDisplayName(displayName) ||
      ProfileValidator.normalizeDisplayName(displayName) != displayName ||
      (role != 'owner' && role != 'member') ||
      joinedAt is! Timestamp ||
      updatedAt is! Timestamp ||
      data['schemaVersion'] != GroupMember.schemaVersion) {
    throw const GroupFailure(GroupFailureKind.invalidData);
  }
  return GroupMember(
    userId: id,
    displayName: displayName,
    role: role == 'owner' ? GroupMemberRole.owner : GroupMemberRole.member,
    joinedAt: joinedAt.toDate(),
    updatedAt: updatedAt.toDate(),
  );
}

GroupInvite groupInviteFromFirestore(String id, Map<String, dynamic> data) {
  final groupId = data['groupId'];
  final groupName = data['groupNameSnapshot'];
  final createdByUid = data['createdByUid'];
  final createdAt = data['createdAt'];
  final expiresAt = data['expiresAt'];
  final revokedAt = data['revokedAt'];
  if (groupId is! String ||
      groupId.isEmpty ||
      groupName is! String ||
      !GroupNameValidator.isValid(groupName) ||
      GroupNameValidator.normalize(groupName) != groupName ||
      createdByUid is! String ||
      createdByUid.isEmpty ||
      createdAt is! Timestamp ||
      expiresAt is! Timestamp ||
      (revokedAt != null && revokedAt is! Timestamp) ||
      data['schemaVersion'] != GroupInvite.schemaVersion) {
    throw const GroupFailure(GroupFailureKind.invalidData);
  }
  return GroupInvite(
    tokenHash: id,
    groupId: groupId,
    groupName: groupName,
    createdByUid: createdByUid,
    createdAt: createdAt.toDate(),
    expiresAt: expiresAt.toDate(),
    revokedAt: (revokedAt as Timestamp?)?.toDate(),
  );
}

GroupFailure _mapFailure(Object error) {
  if (error is GroupFailure) {
    return error;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => const GroupFailure(GroupFailureKind.rulesDenied),
      'unavailable' ||
      'deadline-exceeded' => const GroupFailure(GroupFailureKind.offline),
      'aborted' => const GroupFailure(GroupFailureKind.conflict),
      _ => const GroupFailure(GroupFailureKind.unknown),
    };
  }
  return const GroupFailure(GroupFailureKind.unknown);
}
