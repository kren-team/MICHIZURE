import 'dart:async';

import 'package:flutter/foundation.dart';
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
            return const Center(child: Text('負債が見つかりません。'));
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
        Text(
          '返済中の負債: ${_shortId(debt.id)}',
          key: const Key('selected-debt-id'),
        ),
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
        child: Text('この負債は終了したため、追加のスクワットは送信しません。'),
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
          const AspectRatio(
            key: Key('pose-preview'),
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: AndroidView(
                key: Key('native-squat-camera-container'),
                viewType: MethodChannelSquatDetector.previewViewType,
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
              subtitle: Text('カメラ映像は端末内だけで処理します。'),
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
            _qualityMessage(state.qualityWarning),
            key: const Key('squat-quality-message'),
            textAlign: TextAlign.center,
          ),
        ),
        if (state.lastAnalysisLatencyMs case final latency?)
          Text('端末内判定 ${latency}ms', key: const Key('squat-latency')),
        if (kDebugMode)
          if (state.diagnostics case final diagnostics?)
            _CollapsibleDiagnostics(diagnostics: diagnostics)
          else if (showNativePreview)
            const _LiveSquatDiagnosticsPanel(),
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

final class _SquatDiagnosticsCard extends StatelessWidget {
  const _SquatDiagnosticsCard({required this.diagnostics});

  final SquatDetectorDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('squat-debug-diagnostics'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodySmall,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Debug detector diagnostics'),
              Text('Delegate: ${diagnostics.delegate?.name ?? 'initializing'}'),
              Text('Tracking: ${diagnostics.trackingStatus.name}'),
              Text('Pose detected: ${diagnostics.poseDetected ? 'yes' : 'no'}'),
              Text(
                'Selected side: ${diagnostics.selectedSide?.name ?? 'none'}',
              ),
              Text(
                'Left H/K/A: ${_metric(diagnostics.leftHipConfidence)} / '
                '${_metric(diagnostics.leftKneeConfidence)} / '
                '${_metric(diagnostics.leftAnkleConfidence)}',
              ),
              Text(
                'Right H/K/A: ${_metric(diagnostics.rightHipConfidence)} / '
                '${_metric(diagnostics.rightKneeConfidence)} / '
                '${_metric(diagnostics.rightAnkleConfidence)}',
              ),
              Text('Knee angle: ${_metric(diagnostics.kneeAngle, digits: 1)}°'),
              Text(
                'Hip drop: ${_metric(diagnostics.normalizedHipDrop, digits: 3)}',
              ),
              Text(
                'Knee velocity: '
                '${_metric(diagnostics.kneeAngularVelocity, digits: 1)}°/s',
              ),
              Text(
                'Hip velocity: '
                '${_metric(diagnostics.hipVerticalVelocity, digits: 3)}/s',
              ),
              Text('State: ${diagnostics.state.name}'),
              Text(
                'Latest reject: ${diagnostics.latestRejectReason ?? 'none'}',
              ),
              Text(
                'Accepted / rejected: '
                '${diagnostics.acceptedReps} / ${diagnostics.rejectedAttempts}',
              ),
              Text('Inference latency: ${diagnostics.analysisLatencyMs}ms'),
              Text(
                'Analysis FPS: '
                '${diagnostics.actualAnalysisFps.toStringAsFixed(1)}',
              ),
              Text(
                'Inference p50 / p95: '
                '${diagnostics.inferenceP50Ms ?? '-'} / '
                '${diagnostics.inferenceP95Ms ?? '-'} ms',
              ),
              Text(
                'Pipeline p50 / p95: '
                '${diagnostics.nativePipelineP50Ms ?? '-'} / '
                '${diagnostics.nativePipelineP95Ms ?? '-'} ms',
              ),
              Text(
                'Dropped / busy: '
                '${diagnostics.droppedBeforePreprocessing} / '
                '${diagnostics.rejectedAsBusy}',
              ),
              Text(
                'Results / no pose: '
                '${diagnostics.resultCount} / ${diagnostics.noPoseCount}',
              ),
              Text(
                'Diagnostic events: '
                '${diagnostics.diagnosticEventFps.toStringAsFixed(1)} FPS',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _LiveSquatDiagnosticsPanel extends ConsumerWidget {
  const _LiveSquatDiagnosticsPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(squatDiagnosticsProvider);
    if (diagnostics == null) return const SizedBox.shrink();
    return _CollapsibleDiagnostics(diagnostics: diagnostics);
  }
}

final class _CollapsibleDiagnostics extends StatelessWidget {
  const _CollapsibleDiagnostics({required this.diagnostics});

  final SquatDetectorDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const Key('squat-debug-diagnostics-panel'),
      title: const Text('判定診断（Debug）'),
      initiallyExpanded: false,
      children: [_SquatDiagnosticsCard(diagnostics: diagnostics)],
    );
  }
}

String _metric(double? value, {int digits = 2}) =>
    value?.toStringAsFixed(digits) ?? '-';

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
