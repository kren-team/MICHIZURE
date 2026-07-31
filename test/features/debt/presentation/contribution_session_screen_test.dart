import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    expect(find.text('返済中の負債: debt-1'), findsOneWidget);
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
    expect(find.text('この負債はすでに終了しています。'), findsOneWidget);
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
              detectorReady: true,
              squatSessionId: 'session-12345678',
              debtId: 'debt-1',
              pipelineStatus: SquatPosePipelineStatus.ankleUnavailable,
              qualityWarning: SquatQualityWarning.ankleUnavailable,
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.text('次の動作: 立った姿勢を調整中'), findsOneWidget);
    expect(find.text('足首を認識できません。'), findsOneWidget);
    expect(find.text('端末で検出 1 回'), findsOneWidget);
    expect(find.text('送信待ち 1 回'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows lower-body diagnostics only in debug builds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState.idle(),
            squatState: SquatSessionState(
              status: SquatSessionStatus.running,
              permission: CameraPermissionState.granted,
              detectorState: SquatDetectorState.descending,
              detectedReps: 2,
              lastSequence: 2,
              maximumLocalReps: 10,
              squatSessionId: 'session-12345678',
              debtId: 'debt-1',
              diagnostics: SquatDetectorDiagnostics(
                eventId: 'diagnostics-1',
                occurredAt: DateTime.utc(2026),
                squatSessionId: 'session-12345678',
                poseDetected: true,
                selectedSide: SquatPoseSide.left,
                leftHipConfidence: 0.91,
                leftKneeConfidence: 0.92,
                leftAnkleConfidence: 0.88,
                rightHipConfidence: 0.40,
                rightKneeConfidence: 0.42,
                rightAnkleConfidence: 0.39,
                kneeAngle: 121,
                normalizedHipDrop: 0.13,
                kneeAngularVelocity: -22,
                hipVerticalVelocity: 0.12,
                state: SquatDetectorState.descending,
                latestRejectReason: 'shallowSquat',
                analysisLatencyMs: 85,
                acceptedReps: 2,
                rejectedAttempts: 1,
              ),
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('squat-debug-diagnostics-panel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('squat-debug-diagnostics')), findsOneWidget);
    expect(find.textContaining('Selected side: left'), findsOneWidget);
    expect(find.textContaining('Latest reject: shallowSquat'), findsOneWidget);
    expect(find.textContaining('胸の下から足首まで映してください'), findsOneWidget);
  });

  testWidgets('uses one stable three-by-four native camera container', (
    tester,
  ) async {
    Widget view(SquatDetectorState detectorState) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState.idle(),
            squatState: SquatSessionState(
              status: SquatSessionStatus.running,
              permission: CameraPermissionState.granted,
              detectorState: detectorState,
              detectedReps: 0,
              lastSequence: 0,
              maximumLocalReps: 10,
              detectorReady: true,
              squatSessionId: 'session-12345678',
              debtId: 'debt-1',
            ),
            isFromCache: false,
            hasPendingWrites: false,
            showNativePreview: true,
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(SquatDetectorState.standing));
    final aspect = tester.widget<AspectRatio>(
      find.byKey(const Key('pose-preview')),
    );
    final first = tester.widget<AndroidView>(
      find.byKey(const Key('native-squat-camera-container')),
    );
    expect(aspect.aspectRatio, 3 / 4);

    await tester.pumpWidget(view(SquatDetectorState.descending));
    final second = tester.widget<AndroidView>(
      find.byKey(const Key('native-squat-camera-container')),
    );
    expect(identical(first, second), isTrue);
  });

  testWidgets('shows explicit missing landmark and depth guidance', (
    tester,
  ) async {
    for (final entry in {
      SquatQualityWarning.noPoseDetected: '人物を認識できません。',
      SquatQualityWarning.hipUnavailable: '腰を認識できません。',
      SquatQualityWarning.kneeUnavailable: '膝を認識できません。',
      SquatQualityWarning.ankleUnavailable: '足首を認識できません。',
      SquatQualityWarning.squatDeeper: 'もう少し深くしゃがんでください。',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContributionSessionView(
              debt: _debt(),
              state: const ContributionControllerState.idle(),
              squatState: SquatSessionState(
                status: SquatSessionStatus.running,
                permission: CameraPermissionState.granted,
                detectorState: SquatDetectorState.calibrating,
                detectedReps: 0,
                lastSequence: 0,
                maximumLocalReps: 10,
                detectorReady: true,
                squatSessionId: 'session-12345678',
                debtId: 'debt-1',
                pipelineStatus: switch (entry.key) {
                  SquatQualityWarning.noPoseDetected =>
                    SquatPosePipelineStatus.noPose,
                  SquatQualityWarning.hipUnavailable =>
                    SquatPosePipelineStatus.hipUnavailable,
                  SquatQualityWarning.kneeUnavailable =>
                    SquatPosePipelineStatus.kneeUnavailable,
                  SquatQualityWarning.ankleUnavailable =>
                    SquatPosePipelineStatus.ankleUnavailable,
                  _ => SquatPosePipelineStatus.valid,
                },
                qualityWarning: entry.key,
              ),
              isFromCache: false,
              hasPendingWrites: false,
            ),
          ),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('callback wait never claims that landmarks were recognized', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionSessionView(
            debt: _debt(),
            state: const ContributionControllerState.idle(),
            squatState: const SquatSessionState(
              status: SquatSessionStatus.running,
              permission: CameraPermissionState.granted,
              detectorState: SquatDetectorState.calibrating,
              detectedReps: 0,
              lastSequence: 0,
              maximumLocalReps: 10,
              detectorReady: true,
              squatSessionId: 'session-12345678',
              debtId: 'debt-1',
              pipelineStatus: SquatPosePipelineStatus.awaitingResult,
            ),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ),
    );

    expect(find.text('姿勢判定の結果を待っています。'), findsOneWidget);
    expect(find.text('腰・膝・足首を認識しました。'), findsNothing);
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

  testWidgets('keeps the repayment controls usable at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
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

    expect(find.byKey(const Key('request-camera-permission')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
