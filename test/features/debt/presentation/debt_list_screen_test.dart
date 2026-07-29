import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/presentation/debt_list_screen.dart';
import 'package:michizure/features/group/domain/group_member.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  testWidgets('renders loading, empty and cached states', (tester) async {
    await _pump(tester, debts: const AsyncLoading(), members: const []);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(
      tester,
      debts: const AsyncData(
        DebtSnapshot(
          value: <Debt>[],
          isFromCache: true,
          hasPendingWrites: false,
        ),
      ),
      members: const [],
    );
    expect(find.byKey(const Key('debt-cache-banner')), findsOneWidget);
    expect(find.byKey(const Key('debt-empty-state')), findsOneWidget);
  });

  testWidgets('shows multiple debts including the same failed user', (
    tester,
  ) async {
    await _pump(
      tester,
      debts: AsyncData(
        DebtSnapshot(
          value: [_debt('debt-a', 0), _debt('debt-b', 10)],
          isFromCache: false,
          hasPendingWrites: false,
        ),
      ),
      members: [_member('alice', '野々村 奏')],
    );

    expect(find.byKey(const Key('debt-card-debt-a')), findsOneWidget);
    expect(find.byKey(const Key('debt-card-debt-b')), findsOneWidget);
    expect(find.text('野々村 奏'), findsNWidgets(2));
    expect(find.textContaining('残り 20 回'), findsOneWidget);
    expect(find.textContaining('残り 10 回'), findsOneWidget);
  });

  testWidgets('shows a safe typed listener failure', (tester) async {
    await _pump(
      tester,
      debts: AsyncError(StateError('Firebase raw detail'), StackTrace.current),
      members: const [],
    );

    expect(find.byKey(const Key('debt-list-error')), findsOneWidget);
    expect(find.textContaining('Firebase raw detail'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required AsyncValue<DebtSnapshot<List<Debt>>> debts,
  required List<GroupMember> members,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWithValue(
          AsyncData(
            UserProfile(
              id: 'alice',
              displayName: '野々村 奏',
              photoUrl: null,
              groupId: 'group-1',
              activeTaskSessionId: null,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ),
        activeGroupDebtsProvider.overrideWithValue(debts),
        currentGroupMembersProvider.overrideWithValue(AsyncData(members)),
      ],
      child: const MaterialApp(home: DebtListScreen()),
    ),
  );
  await tester.pump();
}

Debt _debt(String id, int completed) {
  return Debt(
    id: id,
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: id,
    memberCountAtFailure: 2,
    repsPerMember: 10,
    totalReps: 20,
    completedReps: completed,
    status: DebtStatus.active,
    createdAt: DateTime.utc(2026, 1, 1),
    lockExpiresAt: DateTime.utc(2030, 1, 1),
    closedAt: null,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}

GroupMember _member(String id, String name) {
  return GroupMember(
    userId: id,
    displayName: name,
    role: GroupMemberRole.owner,
    joinedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
