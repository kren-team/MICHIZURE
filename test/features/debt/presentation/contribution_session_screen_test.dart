import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/application/contribution_controller.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/presentation/contribution_session_screen.dart';
import 'package:michizure/features/squat/application/squat_session_controller.dart';
import 'package:michizure/features/squat/domain/squat_detector.dart';

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
    expect(find.textContaining('カメラ映像は端末内だけ'), findsOneWidget);
    expect(find.byKey(const Key('request-camera-permission')), findsOneWidget);
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

  testWidgets('shows calibration quality and detected sync states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState(
              isRestoring: false,
              isSubmitting: true,
              detectedCount: 1,
              pendingCount: 1,
              confirmedCount: 0,
              rejectedCount: 0,
            ),
            squatState: const SquatSessionState(
              status: SquatSessionStatus.running,
              permission: CameraPermissionState.granted,
              detectorState: SquatDetectorState.calibrating,
              detectedReps: 1,
              lastSequence: 1,
              maximumLocalReps: 10,
              squatSessionId: 'session-12345678',
              debtId: 'debt-1',
              qualityWarning: SquatQualityWarning.showFullBody,
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.text('判定: 立った姿勢を調整中'), findsOneWidget);
    expect(find.text('全身が映る位置に移動してください。'), findsOneWidget);
    expect(find.text('端末で検出 1 回'), findsOneWidget);
    expect(find.text('送信待ち 1 回'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows camera settings after permanent denial', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState.idle(),
            squatState: const SquatSessionState(
              status: SquatSessionStatus.idle,
              permission: CameraPermissionState.permanentlyDenied,
              detectorState: SquatDetectorState.calibrating,
              detectedReps: 0,
              lastSequence: 0,
              maximumLocalReps: 0,
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('open-camera-settings')), findsOneWidget);
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
