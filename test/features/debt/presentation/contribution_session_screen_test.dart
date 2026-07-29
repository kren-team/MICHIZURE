import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/application/contribution_controller.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/presentation/contribution_session_screen.dart';

import '../support/fake_contribution_repository.dart';

void main() {
  testWidgets('shows the explicit Debt and no manual contribution input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState.idle(),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.text('選択中: debt-1'), findsOneWidget);
    expect(find.text('残り 10 回'), findsOneWidget);
    expect(
      find.byKey(const Key('contribution-no-manual-input')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('shows pending state and offers retry', (tester) async {
    var retried = false;
    final request = contributionRequest();
    final pending = ContributionDelivery(
      request: request,
      status: ContributionSyncStatus.pending,
      failure: const ContributionFailure(ContributionRejectionReason.offline),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: ContributionControllerState(
              isRestoring: false,
              isSubmitting: false,
              detectedCount: 1,
              pendingCount: 1,
              confirmedCount: 0,
              rejectedCount: 0,
              lastDelivery: pending,
            ),
            isFromCache: true,
            hasPendingWrites: false,
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('端末内に保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contribution-retry-button')));
    expect(retried, isTrue);
  });

  testWidgets('shows confirmed and typed rejection without SDK text', (
    tester,
  ) async {
    final request = contributionRequest();
    final rejected = ContributionDelivery(
      request: request,
      status: ContributionSyncStatus.rejected,
      failure: const ContributionFailure(
        ContributionRejectionReason.debtTerminal,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: ContributionControllerState(
              isRestoring: false,
              isSubmitting: false,
              detectedCount: 2,
              pendingCount: 0,
              confirmedCount: 1,
              rejectedCount: 1,
              lastDelivery: rejected,
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.text('確定 1 回'), findsOneWidget);
    expect(find.text('拒否 1 回'), findsOneWidget);
    expect(find.text('このDebtはすでに終了しています。'), findsOneWidget);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });
}

Debt _debt() {
  return Debt(
    id: 'debt-1',
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: 'task-1',
    memberCountAtFailure: 1,
    repsPerMember: 10,
    totalReps: 10,
    completedReps: 0,
    status: DebtStatus.active,
    createdAt: DateTime.utc(2026),
    lockExpiresAt: DateTime.utc(2026, 1, 1, 1),
    closedAt: null,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}
