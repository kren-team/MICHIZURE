import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/group/domain/group.dart';
import 'package:michizure/features/group/domain/group_failure.dart';
import 'package:michizure/features/group/domain/group_member.dart';
import 'package:michizure/features/group/presentation/group_home_screen.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

import '../support/fake_group_repository.dart';

void main() {
  testWidgets('shows create and join paths when the user has no group', (
    tester,
  ) async {
    await _pumpHome(tester, profile: _profile());

    expect(find.byKey(const Key('group-create-route-button')), findsOneWidget);
    expect(find.byKey(const Key('group-join-route-button')), findsOneWidget);
    expect(find.byKey(const Key('device-setup-route-button')), findsOneWidget);
  });

  testWidgets('shows the realtime member snapshot without profile N+1 reads', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      profile: _profile(groupId: 'group-1'),
      group: _group,
      members: _members,
    );

    expect(find.text('朝活チーム'), findsOneWidget);
    expect(find.byKey(const Key('group-member-alice')), findsOneWidget);
    expect(find.byKey(const Key('group-member-bob')), findsOneWidget);
    expect(find.text('野々村 奏'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('a non-owner can leave after confirmation', (tester) async {
    final repository = FakeGroupRepository();
    await _pumpHome(
      tester,
      repository: repository,
      profile: _profile(id: 'bob', displayName: 'Bob', groupId: 'group-1'),
      authUserId: 'bob',
      group: _group,
      members: _members,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-leave-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    expect(repository.leaveCalls, 1);
  });

  testWidgets('shows a safe typed failure when leave fails', (tester) async {
    final repository = FakeGroupRepository()
      ..leaveError = const GroupFailure(GroupFailureKind.conflict);
    await _pumpHome(
      tester,
      repository: repository,
      profile: _profile(id: 'bob', displayName: 'Bob', groupId: 'group-1'),
      authUserId: 'bob',
      group: _group,
      members: _members,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-leave-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group-error-message')), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required UserProfile profile,
  String authUserId = 'alice',
  FakeGroupRepository? repository,
  Group? group,
  List<GroupMember> members = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupRepositoryProvider.overrideWithValue(
          repository ?? FakeGroupRepository(),
        ),
        authStateProvider.overrideWithValue(
          AsyncData(AuthUser(id: authUserId)),
        ),
        currentProfileProvider.overrideWithValue(AsyncData(profile)),
        currentGroupProvider.overrideWithValue(AsyncData(group)),
        currentGroupMembersProvider.overrideWithValue(AsyncData(members)),
        activeGroupDebtsProvider.overrideWithValue(
          const AsyncData(
            DebtSnapshot(
              value: <Debt>[],
              isFromCache: false,
              hasPendingWrites: false,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: GroupHomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

UserProfile _profile({
  String id = 'alice',
  String displayName = '野々村 奏',
  String? groupId,
}) {
  return UserProfile(
    id: id,
    displayName: displayName,
    photoUrl: null,
    groupId: groupId,
    activeTaskSessionId: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

final _group = Group(
  id: 'group-1',
  name: '朝活チーム',
  ownerUid: 'alice',
  memberCount: 2,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _members = [
  GroupMember(
    userId: 'alice',
    displayName: '野々村 奏',
    role: GroupMemberRole.owner,
    joinedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  GroupMember(
    userId: 'bob',
    displayName: 'Bob',
    role: GroupMemberRole.member,
    joinedAt: DateTime.utc(2026, 1, 2),
    updatedAt: DateTime.utc(2026, 1, 2),
  ),
];
