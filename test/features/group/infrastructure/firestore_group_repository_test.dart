import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/group/domain/group_failure.dart';
import 'package:michizure/features/group/domain/group_member.dart';
import 'package:michizure/features/group/infrastructure/firestore_group_repository.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026));

  test('converts valid group and member documents', () {
    final group = groupFromFirestore('group-1', {
      'name': '朝活チーム',
      'ownerUid': 'alice',
      'memberCount': 2,
      'createdAt': timestamp,
      'updatedAt': timestamp,
      'schemaVersion': 1,
    });
    final member = groupMemberFromFirestore('alice', {
      'userId': 'alice',
      'displayNameSnapshot': '野々村 奏',
      'role': 'owner',
      'inviteTokenHash': null,
      'joinedAt': timestamp,
      'updatedAt': timestamp,
      'schemaVersion': 1,
    });

    expect(group.name, '朝活チーム');
    expect(group.memberCount, 2);
    expect(member.displayName, '野々村 奏');
    expect(member.role, GroupMemberRole.owner);
  });

  test('rejects invalid member identity and group count', () {
    expect(
      () => groupMemberFromFirestore('alice', {
        'userId': 'bob',
        'displayNameSnapshot': 'Alice',
        'role': 'member',
        'inviteTokenHash': 'a' * 64,
        'joinedAt': timestamp,
        'updatedAt': timestamp,
        'schemaVersion': 1,
      }),
      throwsA(isA<GroupFailure>()),
    );
    expect(
      () => groupFromFirestore('group-1', {
        'name': 'Group',
        'ownerUid': 'alice',
        'memberCount': 41,
        'createdAt': timestamp,
        'updatedAt': timestamp,
        'schemaVersion': 1,
      }),
      throwsA(isA<GroupFailure>()),
    );
  });
}
