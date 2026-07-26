import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/group/domain/group_failure.dart';
import 'package:michizure/features/group/presentation/group_create_screen.dart';
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
}

Future<void> _pump(
  WidgetTester tester,
  FakeGroupRepository repository,
  Widget screen,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupRepositoryProvider.overrideWithValue(repository),
        currentProfileProvider.overrideWithValue(AsyncData(_profile)),
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
