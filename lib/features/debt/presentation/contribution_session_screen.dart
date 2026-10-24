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
  late final SquatSessionController _squatSessionController;

  @override
  void initState() {
    super.initState();
    _squatSessionController = ref.read(squatSessionControllerProvider.notifier);
  }

  @override
  void dispose() {
    unawaited(_squatSessionController.stop());
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
      appBar: AppBar(
        title: const Text('スクワットで返済'),
        actions: const [MichizureHomeAction()],
      ),
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
    final members = ref.watch(currentGroupMembersProvider).value ?? const [];
    final debtorName = members
        .where((member) => member.userId == debt.failedUserId)
        .map((member) => member.displayName)
        .firstOrNull;
    return ContributionSessionView(
      debt: debt,
      debtorName: debtorName,
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
    );
  }
}

final class ContributionSessionView extends StatelessWidget {
  const ContributionSessionView({
    required this.debt,
    this.debtorName,
    required this.state,
    required this.isFromCache,
    required this.hasPendingWrites,
    this.squatState = const SquatSessionState.initial(),
    this.showNativePreview = false,
    this.onRequestPermission,
    this.onOpenSettings,
    this.onStart,
    this.onStop,
    super.key,
  });

  final Debt debt;

  /// 負債を発生させたメンバーの表示名。解決できない場合はnull。
  final String? debtorName;
  final ContributionControllerState state;
  final SquatSessionState squatState;
  final bool isFromCache;
  final bool hasPendingWrites;
  final bool showNativePreview;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isActive = debt.status == DebtStatus.active;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MichizureSpacing.page,
        4,
        MichizureSpacing.page,
        32,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(MichizureSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${debtorName ?? 'グループメンバー'}の負債を返済中',
                        key: const Key('selected-debt-label'),
                        style: MichizureTextStyles.overline,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    MichizureStatusPill(
                      label: isActive ? '返済中' : '終了',
                      icon: isActive
                          ? Icons.directions_run
                          : Icons.check_circle_outline,
                      color: isActive
                          ? MichizureColors.accent
                          : MichizureColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: Tween(begin: 1.15, end: 1.0).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [?current],
                  ),
                  child: MichizureRepCount(
                    key: ValueKey(debt.remainingReps),
                    reps: debt.remainingReps,
                    textKey: const Key('contribution-session-remaining'),
                    color: isActive
                        ? MichizureColors.accent
                        : MichizureColors.success,
                  ),
                ),
                const SizedBox(height: 14),
                MichizureProgressBar(
                  value: debt.totalReps == 0
                      ? 0
                      : debt.completedReps / debt.totalReps,
                  color: isActive
                      ? MichizureColors.accent
                      : MichizureColors.success,
                ),
                const SizedBox(height: 8),
                Text(
                  '${debt.completedReps} / ${debt.totalReps} 回 返済済み',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (state.lastDelivery case final delivery?
            when delivery.status == ContributionSyncStatus.rejected)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _rejectionMessage(delivery.failure?.reason),
              key: const Key('contribution-delivery-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: MichizureSpacing.item),
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
        if (squatState.isRunning ||
            squatState.detectedReps > 0 ||
            state.pendingCount > 0 ||
            state.confirmedCount > 0 ||
            state.rejectedCount > 0) ...[
          const MichizureSectionHeader(title: '返済の反映状況'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Row(
                children: [
                  _SyncStat(
                    label: '端末で検出',
                    value: squatState.detectedReps,
                    textKey: const Key('squat-detected-count'),
                  ),
                  _SyncStat(
                    label: '送信待ち',
                    value: state.pendingCount,
                    textKey: const Key('contribution-pending-count'),
                  ),
                  _SyncStat(
                    label: '確定',
                    value: state.confirmedCount,
                    textKey: const Key('contribution-confirmed-count'),
                    color: MichizureColors.success,
                  ),
                  _SyncStat(
                    label: '拒否',
                    value: state.rejectedCount,
                    textKey: const Key('contribution-rejected-count'),
                    color: state.rejectedCount > 0
                        ? MichizureColors.error
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
        if (state.isRestoring || state.isSubmitting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

final class _SyncStat extends StatelessWidget {
  const _SyncStat({
    required this.label,
    required this.value,
    required this.textKey,
    this.color,
  });

  final String label;
  final int value;
  final Key textKey;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$label $value 回',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              '$value',
              key: textKey,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: value == 0 ? MichizureColors.textTertiary : color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
            ),
          ],
        ),
      ),
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
      return _SessionSetupCard(
        action: MichizurePrimaryButton(
          buttonKey: const Key('open-camera-settings'),
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
          child: const Text('設定でカメラを許可'),
        ),
      );
    }
    if (state.permission != CameraPermissionState.granted) {
      return _SessionSetupCard(
        action: MichizurePrimaryButton(
          buttonKey: const Key('request-camera-permission'),
          onPressed: state.status == SquatSessionStatus.requestingPermission
              ? null
              : onRequestPermission,
          icon: const Icon(Icons.videocam_outlined),
          child: const Text('カメラを許可して準備'),
        ),
      );
    }
    if (!state.isRunning) {
      return _SessionSetupCard(
        action: MichizurePrimaryButton(
          buttonKey: const Key('start-squat-session'),
          accent: true,
          onPressed: state.status == SquatSessionStatus.starting
              ? null
              : onStart,
          icon: const Icon(Icons.directions_run),
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
        const SizedBox(height: MichizureSpacing.item),
        if (!state.detectorReady)
          const Card(
            key: Key('pose-model-loading'),
            child: ListTile(
              leading: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              title: Text('姿勢判定を準備しています'),
              subtitle: Text('全身が映る位置でお待ちください。'),
            ),
          ),
        _DetectorStateBanner(
          detectorState: state.detectorState,
          qualityMessage: _qualityMessage(
            state.pipelineStatus,
            state.qualityWarning,
          ),
          isQualityOk:
              state.pipelineStatus == SquatPosePipelineStatus.valid &&
              state.qualityWarning == null,
        ),
        if (state.failure case final failure?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _detectorFailureMessage(failure.reason),
              key: const Key('squat-detector-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          '胸の下から足首まで映してください。'
          'カメラに対して斜め30〜45度または横向きになると判定しやすくなります。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: MichizureColors.textTertiary),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('stop-squat-session'),
          onPressed: state.status == SquatSessionStatus.stopping
              ? null
              : onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('返済を終了'),
        ),
      ],
    );
  }
}

final class _SessionSetupCard extends StatelessWidget {
  const _SessionSetupCard({required this.action});

  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(MichizureSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('はじめる前に', style: MichizureTextStyles.overline),
            const SizedBox(height: 14),
            const _SetupStep(number: 1, text: '端末を腰くらいの高さに立てかける'),
            const _SetupStep(number: 2, text: '2〜3歩下がり、胸の下から足首までを映す'),
            const _SetupStep(number: 3, text: 'カメラに対して斜め30〜45度を向く'),
            const SizedBox(height: 18),
            action,
            const SizedBox(height: 10),
            const Text(
              '映像は端末内だけで判定し、保存・送信しません。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: MichizureColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SetupStep extends StatelessWidget {
  const _SetupStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MichizureColors.elevatedSurface,
            ),
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: MichizureColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DetectorStateBanner extends StatelessWidget {
  const _DetectorStateBanner({
    required this.detectorState,
    required this.qualityMessage,
    required this.isQualityOk,
  });

  final SquatDetectorState detectorState;
  final String qualityMessage;
  final bool isQualityOk;

  @override
  Widget build(BuildContext context) {
    final emphasized = detectorState == SquatDetectorState.bottom;
    return Card(
      color: emphasized
          ? MichizureColors.accent.withValues(alpha: 0.16)
          : MichizureColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              _stateIcon(detectorState),
              color: emphasized
                  ? MichizureColors.accent
                  : MichizureColors.textPrimary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '次の動作: ${_stateLabel(detectorState)}',
                      key: const Key('squat-detector-state'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          isQualityOk ? Icons.check_circle : Icons.info_outline,
                          size: 14,
                          color: isQualityOk
                              ? MichizureColors.success
                              : MichizureColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            qualityMessage,
                            key: const Key('squat-quality-message'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _stateIcon(SquatDetectorState state) {
  return switch (state) {
    SquatDetectorState.calibrating => Icons.accessibility_new,
    SquatDetectorState.standing => Icons.play_arrow_rounded,
    SquatDetectorState.descending => Icons.south,
    SquatDetectorState.bottom => Icons.north,
    SquatDetectorState.ascending => Icons.north,
  };
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

String _rejectionMessage(ContributionRejectionReason? reason) {
  return switch (reason) {
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
  };
}
