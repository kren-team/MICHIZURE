import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
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
      body: debt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            debtFailureMessage(error),
            key: const Key('contribution-session-error'),
          ),
        ),
        data: (snapshot) {
          final value = snapshot.value;
          if (value == null) {
            return const Center(child: Text('Debtが見つかりません。'));
          }
          return ContributionSessionView(
            debt: value,
            state: syncState,
            squatState: squatState,
            isFromCache: snapshot.isFromCache,
            hasPendingWrites: snapshot.hasPendingWrites,
            showNativePreview: true,
            onRequestPermission: () => ref
                .read(squatSessionControllerProvider.notifier)
                .requestPermission(),
            onOpenSettings: () => ref
                .read(squatSessionControllerProvider.notifier)
                .openAppSettings(),
            onStart: () => ref
                .read(squatSessionControllerProvider.notifier)
                .start(debtId: value.id, remainingReps: value.remainingReps),
            onStop: () =>
                ref.read(squatSessionControllerProvider.notifier).stop(),
            onRetry: syncState.pendingCount > 0
                ? () => ref
                      .read(contributionControllerProvider.notifier)
                      .retryPending()
                : null,
          );
        },
      ),
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
      padding: const EdgeInsets.all(24),
      children: [
        Text('選択中: ${debt.id}', key: const Key('selected-debt-id')),
        const SizedBox(height: 12),
        Text(
          '残り ${debt.remainingReps} 回',
          key: const Key('contribution-session-remaining'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('状態: ${debt.status == DebtStatus.active ? '返済中' : '終了'}'),
        if (isFromCache || hasPendingWrites)
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('同期確定前の情報が含まれます'),
              subtitle: Text('接続後、サーバーで確定した回数へ更新されます。'),
            ),
          ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('カメラ映像は端末内だけで処理します'),
            subtitle: Text('画像・動画・姿勢座標は保存せず、外部へ送信しません。'),
          ),
        ),
        _SquatControls(
          debt: debt,
          state: squatState,
          showNativePreview: showNativePreview,
          onRequestPermission: onRequestPermission,
          onOpenSettings: onOpenSettings,
          onStart: onStart,
          onStop: onStop,
        ),
        const Divider(height: 32),
        Text('返済の同期状態', style: Theme.of(context).textTheme.titleMedium),
        Text(
          '端末で検出 ${squatState.detectedReps} 回',
          key: const Key('squat-detected-count'),
        ),
        Text('Outbox投入 ${state.detectedCount} 回'),
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
        child: Text('このDebtは終了したため、追加のスクワットは送信しません。'),
      );
    }
    if (state.permission == CameraPermissionState.permanentlyDenied) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: FilledButton(
          key: const Key('open-camera-settings'),
          onPressed: onOpenSettings,
          child: const Text('設定でカメラを許可'),
        ),
      );
    }
    if (state.permission != CameraPermissionState.granted) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: FilledButton(
          key: const Key('request-camera-permission'),
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
        child: FilledButton.icon(
          key: const Key('start-squat-session'),
          onPressed: state.status == SquatSessionStatus.starting
              ? null
              : onStart,
          icon: const Icon(Icons.camera_alt),
          label: const Text('スクワット返済を開始'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showNativePreview)
          const SizedBox(
            key: Key('pose-preview'),
            height: 420,
            child: ClipRect(
              child: AndroidView(
                viewType: MethodChannelSquatDetector.previewViewType,
              ),
            ),
          ),
        const Text('1人で全身と顔が映る位置に立ってください。'),
        Text(
          '判定: ${_stateLabel(state.detectorState)}',
          key: const Key('squat-detector-state'),
        ),
        Text(
          _qualityMessage(state.qualityWarning),
          key: const Key('squat-quality-message'),
        ),
        if (state.lastAnalysisLatencyMs case final latency?)
          Text('端末内判定 ${latency}ms', key: const Key('squat-latency')),
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
    SquatDetectorState.calibrating => '立った姿勢を調整中',
    SquatDetectorState.standing => '準備OK',
    SquatDetectorState.descending => 'しゃがんでいます',
    SquatDetectorState.bottom => '深さOK・立ち上がってください',
    SquatDetectorState.ascending => '最後まで立ち上がってください',
  };
}

String _qualityMessage(SquatQualityWarning? warning) {
  return switch (warning) {
    null => '全身を認識しています。',
    SquatQualityWarning.showFullBody => '全身が映る位置に移動してください。',
    SquatQualityWarning.moveFartherBack => 'カメラから少し離れてください。',
    SquatQualityWarning.moveCloser => 'カメラへ少し近づいてください。',
    SquatQualityWarning.lowLightOrConfidence => '明るい場所で全身を映してください。',
    SquatQualityWarning.holdStillToCalibrate => '立った姿勢で少し静止してください。',
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
    SquatDetectorFailureReason.unknown => '端末内の姿勢判定でエラーが発生しました。',
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
      ContributionRejectionReason.debtFull => 'このDebtはすでに終了しています。',
      ContributionRejectionReason.deadlineReached => 'Debtの期限が終了しました。',
      ContributionRejectionReason.unauthorized => 'このDebtを返済する権限がありません。',
      ContributionRejectionReason.invalidRequest ||
      ContributionRejectionReason.conflict ||
      ContributionRejectionReason.malformedData => '返済データを確認できませんでした。',
      ContributionRejectionReason.debtNotFound => 'Debtが見つかりません。',
      ContributionRejectionReason.outboxFull => '送信待ちが上限です。接続後に再試行してください。',
      ContributionRejectionReason.offline ||
      ContributionRejectionReason.unknown ||
      null => '返済を確定できませんでした。再試行してください。',
    },
  };
}
