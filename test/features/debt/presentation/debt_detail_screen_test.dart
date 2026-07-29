import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/presentation/debt_detail_screen.dart';
import 'package:michizure/features/group/domain/group_member.dart';

void main() {
  testWidgets('renders Debt aggregate and read-only member summaries', (
    tester,
  ) async {
    final debt = _debt();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          debtProvider('debt-1').overrideWithValue(
            AsyncData(
              DebtSnapshot(
                value: debt,
                isFromCache: false,
                hasPendingWrites: false,
              ),
            ),
          ),
          debtContributionsProvider('debt-1').overrideWithValue(
            AsyncData(
              DebtSnapshot(
                value: [
                  DebtContributionSummary(
                    userId: 'bob',
                    totalReps: 12,
                    lastEventId: 'event-12',
                    lastContributedAt: DateTime.utc(2026),
                  ),
                ],
                isFromCache: false,
                hasPendingWrites: false,
              ),
            ),
          ),
          currentGroupMembersProvider.overrideWithValue(
            AsyncData([_member('alice', '野々村 奏'), _member('bob', 'カナデ')]),
          ),
        ],
        child: const MaterialApp(home: DebtDetailScreen(debtId: 'debt-1')),
      ),
    );
    await tester.pump();

    expect(find.text('野々村 奏'), findsOneWidget);
    expect(find.byKey(const Key('debt-detail-remaining')), findsOneWidget);
    expect(find.text('カナデ'), findsOneWidget);
    expect(find.text('12 回'), findsOneWidget);
    expect(find.textContaining('次のPhase'), findsOneWidget);
  });

  testWidgets('renders terminal status without contribution write controls', (
    tester,
  ) async {
    final debt = _debt(
      status: DebtStatus.expired,
      closedAt: DateTime.utc(2026, 1, 1, 0, 30),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          debtProvider('debt-1').overrideWithValue(
            AsyncData(
              DebtSnapshot(
                value: debt,
                isFromCache: true,
                hasPendingWrites: false,
              ),
            ),
          ),
          debtContributionsProvider('debt-1').overrideWithValue(
            const AsyncData(
              DebtSnapshot(
                value: <DebtContributionSummary>[],
                isFromCache: true,
                hasPendingWrites: false,
              ),
            ),
          ),
          currentGroupMembersProvider.overrideWithValue(const AsyncData([])),
        ],
        child: const MaterialApp(home: DebtDetailScreen(debtId: 'debt-1')),
      ),
    );
    await tester.pump();

    expect(find.text('状態: 期限終了'), findsOneWidget);
    expect(find.byKey(const Key('debt-detail-cache-banner')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}

Debt _debt({DebtStatus status = DebtStatus.active, DateTime? closedAt}) {
  return Debt(
    id: 'debt-1',
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: 'debt-1',
    memberCountAtFailure: 2,
    repsPerMember: 10,
    totalReps: 20,
    completedReps: 0,
    status: status,
    createdAt: DateTime.utc(2026),
    lockExpiresAt: DateTime.utc(2026, 1, 1, 0, 30),
    closedAt: closedAt,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}

GroupMember _member(String id, String name) {
  return GroupMember(
    userId: id,
    displayName: name,
    role: GroupMemberRole.member,
    joinedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
