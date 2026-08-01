import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/group/domain/group_failure.dart';
import 'package:michizure/features/group/presentation/group_create_screen.dart';
import 'package:michizure/features/group/presentation/group_invite_screen.dart';
import 'package:michizure/features/group/presentation/group_join_screen.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

import '../support/fake_group_repository.dart';

void main() {
  testWidgets('submits a valid group creation', (tester) async {
    final repository = FakeGroupRepository();
    await _pump(tester, repository, const GroupCreateScreen());

    await tester.enterText(find.byKey(const Key('group-name-field')), '朝活チーム');
    await tester.tap(find.byKey(const Key('group-create-button')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.lastGroupName, '朝活チーム');
  });

  testWidgets('renders a typed invalid invite failure safely', (tester) async {
    final repository = FakeGroupRepository()
      ..joinError = const GroupFailure(GroupFailureKind.invalidInvite);
    await _pump(tester, repository, const GroupJoinScreen());

    await tester.enterText(
      find.byKey(const Key('group-invite-token-field')),
      'invalid-token',
    );
    await tester.tap(find.byKey(const Key('group-join-button')));
    await tester.pumpAndSettle();

    expect(repository.joinCalls, 1);
    expect(find.text('招待コードが正しくありません。'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });

  testWidgets('creates and revokes an invite without exposing its hash', (
    tester,
  ) async {
    final repository = FakeGroupRepository();
    await _pump(
      tester,
      repository,
      const GroupInviteScreen(),
      profile: _profileWithGroup,
    );

    await tester.tap(find.byKey(const Key('group-create-invite-button')));
    await tester.pumpAndSettle();

    expect(repository.createInviteCalls, 1);
    expect(find.byKey(const Key('group-issued-token')), findsOneWidget);
    expect(find.text('raw-token'), findsOneWidget);
    expect(find.text('a' * 64), findsNothing);

    await tester.tap(find.byKey(const Key('group-revoke-invite-button')));
    await tester.pumpAndSettle();
    expect(find.text('招待を取り消しますか？'), findsOneWidget);
    await tester.tap(find.text('取り消す'));
    await tester.pumpAndSettle();

    expect(repository.revokeInviteCalls, 1);
    expect(find.byKey(const Key('group-issued-token')), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeGroupRepository repository,
  Widget screen, {
  UserProfile? profile,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupRepositoryProvider.overrideWithValue(repository),
        currentProfileProvider.overrideWithValue(
          AsyncData(profile ?? _profile),
        ),
      ],
      child: MaterialApp(home: screen),
    ),
  );
}

final _profile = UserProfile(
  id: 'alice',
  displayName: '野々村 奏',
  photoUrl: null,
  groupId: null,
  activeTaskSessionId: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _profileWithGroup = UserProfile(
  id: 'alice',
  displayName: '野々村 奏',
  photoUrl: null,
  groupId: 'group-1',
  activeTaskSessionId: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
