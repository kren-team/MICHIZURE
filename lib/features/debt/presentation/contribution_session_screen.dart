import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/providers.dart';
import '../../../core/presentation/app_components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../squat/application/squat_session_controller.dart';
import '../../squat/domain/squat_detector.dart';
import '../../squat/infrastructure/squat_detector_channel.dart';
import '../application/contribution_controller.dart';
import '../domain/contribution.dart';
import '../domain/debt.dart';
import 'debt_failure_message.dart';

final class ContributionSessionScreen extends ConsumerStatefulWidget {
  const ContributionSessionScreen({required this.debtId, super.key});

  final String debtId;

  @override
  ConsumerState<ContributionSessionScreen> createState() =>
      _ContributionSessionScreenState();
}

final class _ContributionSessionScreenState
    extends ConsumerState<ContributionSessionScreen> {
  DebtSnapshot<Debt?>? _lastDebtSnapshot;

  @override
  void dispose() {
    unawaited(ref.read(squatSessionControllerProvider.notifier).stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debt = ref.watch(debtProvider(widget.debtId));
    final syncState = ref.watch(contributionControllerProvider);
    final squatState = ref.watch(squatSessionControllerProvider);
    final latestSnapshot = debt.value;
    if (latestSnapshot?.value != null) {
      _lastDebtSnapshot = latestSnapshot;
    }
    final visibleSnapshot = latestSnapshot?.value != null
        ? latestSnapshot
        : (debt.isLoading ? _lastDebtSnapshot : null);
    ref.listen(debtProvider(widget.debtId), (_, next) {
      final terminal = next.value?.value;
      if (terminal != null && terminal.isTerminal) {
        unawaited(
          ref
              .read(squatSessionControllerProvider.notifier)
              .stopForTerminalDebt(terminal),
        );
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('スクワットで返済')),
      body: visibleSnapshot != null
          ? _buildSession(visibleSnapshot, syncState, squatState)
          : debt.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(
                  debtFailureMessage(error),
                  key: const Key('contribution-session-error'),
                ),
              ),
              data: (_) => const Center(child: Text('負債が見つかりません。')),
            ),
    );
  }

  Widget _buildSession(
    DebtSnapshot<Debt?> snapshot,
    ContributionControllerState syncState,
    SquatSessionState squatState,
  ) {
    final debt = snapshot.value!;
    return ContributionSessionView(
      debt: debt,
      state: syncState,
      squatState: squatState,
      isFromCache: snapshot.isFromCache,
      hasPendingWrites: snapshot.hasPendingWrites,
      showNativePreview: true,
      onRequestPermission: () =>
          ref.read(squatSessionControllerProvider.notifier).requestPermission(),
      onOpenSettings: () =>
          ref.read(squatSessionControllerProvider.notifier).openAppSettings(),
      onStart: () => ref
          .read(squatSessionControllerProvider.notifier)
          .start(debtId: debt.id, remainingReps: debt.remainingReps),
      onStop: () => ref.read(squatSessionControllerProvider.notifier).stop(),
      onRetry: syncState.pendingCount > 0
          ? () =>
                ref.read(contributionControllerProvider.notifier).retryPending()
          : null,
    );
  }
}

final class ContributionSessionView extends StatelessWidget {
  const ContributionSessionView({
    required this.debt,
    required this.state,
    required this.isFromCache,
    required this.hasPendingWrites,
    this.squatState = const SquatSessionState.initial(),
    this.showNativePreview = false,
    this.onRequestPermission,
    this.onOpenSettings,
    this.onStart,
    this.onStop,
    this.onRetry,
    super.key,
  });

  final Debt debt;
  final ContributionControllerState state;
  final SquatSessionState squatState;
  final bool isFromCache;
  final bool hasPendingWrites;
  final bool showNativePreview;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MichizureSpacing.page),
      children: [
        Text(
          '返済中の負債: ${_shortId(debt.id)}',
          key: const Key('selected-debt-id'),
        ),
        const SizedBox(height: 12),
        MichizureMetricCard(
          label: 'スクワット返済',
          value: '残り ${debt.remainingReps} 回',
          valueKey: const Key('contribution-session-remaining'),
          icon: Icons.fitness_center,
          child: MichizureStatusPill(
            label: debt.status == DebtStatus.active ? '返済中' : '終了',
            icon: debt.status == DebtStatus.active
                ? Icons.directions_run
                : Icons.check_circle_outline,
            color: debt.status == DebtStatus.active
                ? MichizureColors.pink
                : MichizureColors.success,
          ),
        ),
        if (isFromCache || hasPendingWrites)
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('同期確定前の情報が含まれます'),
              subtitle: Text('接続後、サーバーで確定した回数へ更新されます。'),
            ),
          ),
        if (state.lastDelivery case final delivery?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _deliveryMessage(delivery.status, delivery.failure?.reason),
              key: const Key('contribution-delivery-message'),
              style: delivery.status == ContributionSyncStatus.rejected
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
        if (onRetry != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              key: const Key('contribution-retry-button'),
              onPressed: onRetry,
              child: const Text('送信を再試行'),
            ),
          ),
        const SizedBox(height: 16),
        _SquatControls(
          key: const ValueKey('persistent-squat-controls'),
          debt: debt,
          state: squatState,
          showNativePreview: showNativePreview,
          onRequestPermission: onRequestPermission,
          onOpenSettings: onOpenSettings,
          onStart: onStart,
          onStop: onStop,
        ),
        const Divider(height: 32),
        Text('返済の反映状況', style: Theme.of(context).textTheme.titleMedium),
        Text(
          '端末で検出 ${squatState.detectedReps} 回',
          key: const Key('squat-detected-count'),
        ),
        Text('検出を保存 ${state.detectedCount} 回'),
        Text(
          '送信待ち ${state.pendingCount} 回',
          key: const Key('contribution-pending-count'),
        ),
        Text(
          '確定 ${state.confirmedCount} 回',
          key: const Key('contribution-confirmed-count'),
        ),
        Text(
          '拒否 ${state.rejectedCount} 回',
          key: const Key('contribution-rejected-count'),
        ),
        if (state.isRestoring || state.isSubmitting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

final class _SquatControls extends StatelessWidget {
  const _SquatControls({
    required this.debt,
    required this.state,
    required this.showNativePreview,
    this.onRequestPermission,
    this.onOpenSettings,
    this.onStart,
    this.onStop,
    super.key,
  });

  final Debt debt;
  final SquatSessionState state;
  final bool showNativePreview;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    if (debt.isTerminal) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('この負債は終了したため、追加のスクワットは送信しません。'),
      );
    }
    if (state.permission == CameraPermissionState.permanentlyDenied) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: MichizurePrimaryButton(
          buttonKey: const Key('open-camera-settings'),
          onPressed: onOpenSettings,
          child: const Text('設定でカメラを許可'),
        ),
      );
    }
    if (state.permission != CameraPermissionState.granted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: MichizurePrimaryButton(
          buttonKey: const Key('request-camera-permission'),
          onPressed: state.status == SquatSessionStatus.requestingPermission
              ? null
              : onRequestPermission,
          child: const Text('カメラを許可して準備'),
        ),
      );
    }
    if (!state.isRunning) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: MichizurePrimaryButton(
          buttonKey: const Key('start-squat-session'),
          onPressed: state.status == SquatSessionStatus.starting
              ? null
              : onStart,
          icon: const Icon(Icons.camera_alt),
          child: const Text('スクワット返済を開始'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNativePreview)
          AspectRatio(
            key: const Key('pose-preview'),
            aspectRatio: 3 / 4,
            child: const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: AndroidView(
                key: Key('native-squat-camera-container'),
                viewType: MethodChannelSquatDetector.previewViewType,
                creationParams:
                    MethodChannelSquatDetector.previewCreationParams,
                creationParamsCodec: StandardMessageCodec(),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (!state.detectorReady)
          const Card(
            key: Key('pose-model-loading'),
            child: ListTile(
              leading: CircularProgressIndicator(),
              title: Text('姿勢判定を準備しています'),
              subtitle: Text('全身が映る位置でお待ちください。'),
            ),
          ),
        const Text(
          '胸の下から足首まで映してください。'
          'カメラに対して斜め30〜45度または横向きになると判定しやすくなります。',
          textAlign: TextAlign.center,
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            '次の動作: ${_stateLabel(state.detectorState)}',
            key: const Key('squat-detector-state'),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Text(
            _qualityMessage(state.pipelineStatus, state.qualityWarning),
            key: const Key('squat-quality-message'),
            textAlign: TextAlign.center,
          ),
        ),
        if (state.failure case final failure?)
          Text(
            _detectorFailureMessage(failure.reason),
            key: const Key('squat-detector-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('stop-squat-session'),
          onPressed: state.status == SquatSessionStatus.stopping
              ? null
              : onStop,
          child: const Text('返済を終了'),
        ),
      ],
    );
  }
}

String _stateLabel(SquatDetectorState state) {
  return switch (state) {
    SquatDetectorState.calibrating => '姿勢を確認しています',
    SquatDetectorState.standing => 'スクワットを開始してください',
    SquatDetectorState.descending => 'しゃがんでいます',
    SquatDetectorState.bottom => '深さOK・立ち上がってください',
    SquatDetectorState.ascending => '最後まで立ち上がってください',
  };
}

String _qualityMessage(
  SquatPosePipelineStatus pipelineStatus,
  SquatQualityWarning? warning,
) {
  final pipelineMessage = switch (pipelineStatus) {
    SquatPosePipelineStatus.initializing => '姿勢判定を準備しています。',
    SquatPosePipelineStatus.awaitingResult => '姿勢判定の結果を待っています。',
    SquatPosePipelineStatus.noPose => '人物を認識できません。',
    SquatPosePipelineStatus.hipUnavailable => '腰を認識できません。',
    SquatPosePipelineStatus.kneeUnavailable => '膝を認識できません。',
    SquatPosePipelineStatus.ankleUnavailable => '足首を認識できません。',
    SquatPosePipelineStatus.confidenceInsufficient => '明るい場所で腰・膝・足首を映してください。',
    SquatPosePipelineStatus.failed => '姿勢を確認できません。もう一度準備してください。',
    SquatPosePipelineStatus.valid => null,
  };
  if (pipelineMessage != null) return pipelineMessage;
  return switch (warning) {
    null => '腰・膝・足首を認識しました。',
    SquatQualityWarning.noPoseDetected => '人物を認識できません。',
    SquatQualityWarning.hipUnavailable => '腰を認識できません。',
    SquatQualityWarning.kneeUnavailable => '膝を認識できません。',
    SquatQualityWarning.ankleUnavailable => '足首を認識できません。',
    SquatQualityWarning.moveFartherBack => 'カメラから少し離れてください。',
    SquatQualityWarning.moveCloser => 'カメラへ少し近づいてください。',
    SquatQualityWarning.lowLightOrConfidence => '明るい場所で腰・膝・足首を映してください。',
    SquatQualityWarning.holdStillToCalibrate => '立った姿勢で少し静止してください。',
    SquatQualityWarning.squatDeeper => 'もう少し深くしゃがんでください。',
    SquatQualityWarning.tooDeep => '深くしゃがみすぎています。立った姿勢へ戻ってください。',
    SquatQualityWarning.cameraUnavailable => 'カメラを利用できません。',
  };
}

String _detectorFailureMessage(SquatDetectorFailureReason reason) {
  return switch (reason) {
    SquatDetectorFailureReason.permissionDenied => 'カメラ権限が必要です。',
    SquatDetectorFailureReason.permissionPermanentlyDenied =>
      'Android設定からカメラを許可してください。',
    SquatDetectorFailureReason.cameraUnavailable => 'カメラを開始できませんでした。',
    SquatDetectorFailureReason.sessionConflict => '別の返済セッションが動作中です。',
    SquatDetectorFailureReason.contractMismatch ||
    SquatDetectorFailureReason.malformedEvent => '判定機能の互換性を確認できません。',
    SquatDetectorFailureReason.nativeUnavailable ||
    SquatDetectorFailureReason.unknown => '姿勢を確認できません。もう一度準備してください。',
  };
}

String _deliveryMessage(
  ContributionSyncStatus status,
  ContributionRejectionReason? reason,
) {
  return switch (status) {
    ContributionSyncStatus.detected => 'スクワットを検出しました。',
    ContributionSyncStatus.pending => 'オフラインです。端末内に保存して再送します。',
    ContributionSyncStatus.confirmed => '1回の返済がサーバーで確定しました。',
    ContributionSyncStatus.rejected => switch (reason) {
      ContributionRejectionReason.debtTerminal ||
      ContributionRejectionReason.debtFull => 'この負債はすでに終了しています。',
      ContributionRejectionReason.deadlineReached => '負債の期限が終了しました。',
      ContributionRejectionReason.unauthorized => 'この負債を返済する権限がありません。',
      ContributionRejectionReason.invalidRequest ||
      ContributionRejectionReason.conflict ||
      ContributionRejectionReason.malformedData => '返済データを確認できませんでした。',
      ContributionRejectionReason.debtNotFound => '負債が見つかりません。',
      ContributionRejectionReason.outboxFull => '送信待ちが上限です。接続後に再試行してください。',
      ContributionRejectionReason.offline ||
      ContributionRejectionReason.unknown ||
      null => '返済を確定できませんでした。再試行してください。',
    },
  };
}

String _shortId(String value) {
  return value.length <= 8 ? value : value.substring(0, 8);
}
