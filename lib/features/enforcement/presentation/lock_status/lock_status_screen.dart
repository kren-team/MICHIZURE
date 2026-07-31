import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/presentation/app_components.dart';
import '../../../../core/presentation/app_theme.dart';
import '../../../debt/application/debt_lock_release_controller.dart';
import '../../../debt/presentation/debt_failure_message.dart';
import '../../application/app_lock_controller.dart';
import '../../domain/app_lock.dart';
import '../enforcement_failure_message.dart';

final class LockStatusScreen extends ConsumerStatefulWidget {
  const LockStatusScreen({super.key});

  @override
  ConsumerState<LockStatusScreen> createState() => _LockStatusScreenState();
}

final class _LockStatusScreenState extends ConsumerState<LockStatusScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockControllerProvider);
    final remoteRelease = ref.watch(debtLockReleaseStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('アプリ封印状態')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _LockError(
          message: enforcementFailureMessage(error),
          onRetry: () =>
              ref.read(appLockControllerProvider.notifier).reconcile(),
        ),
        data: (value) => _LockStateView(
          state: value,
          now: ref.read(clockProvider).now().toUtc(),
          remoteReleaseFailure: remoteRelease.failure,
          onRetryRemoteRelease: () =>
              ref.read(debtLockReleaseControllerProvider.notifier).retry(),
          onReconcile: () =>
              ref.read(appLockControllerProvider.notifier).reconcile(),
        ),
      ),
    );
  }
}

final class _LockStateView extends StatelessWidget {
  const _LockStateView({
    required this.state,
    required this.now,
    required this.remoteReleaseFailure,
    required this.onRetryRemoteRelease,
    required this.onReconcile,
  });

  final AppLockState state;
  final DateTime now;
  final Object? remoteReleaseFailure;
  final VoidCallback onRetryRemoteRelease;
  final VoidCallback onReconcile;

  @override
  Widget build(BuildContext context) {
    final active = state.obligations
        .where((obligation) => obligation.isUnresolved)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(MichizureSpacing.page),
      children: [
        Card(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: MichizureGradients.subtle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(MichizureSpacing.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MichizureStatusPill(
                    label: state.hasActiveLock ? '封印中' : '利用可能',
                    icon: state.hasActiveLock ? Icons.lock : Icons.lock_open,
                    color: state.hasActiveLock
                        ? MichizureColors.pink
                        : MichizureColors.success,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    state.hasActiveLock ? 'アプリを封印中' : '現在の封印はありません',
                    key: const Key('lock-status-title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.hasActiveLock
                        ? '有効な対象 ${state.effectiveTargetCount}件'
                        : '負債の完済または期限到達で解除されます',
                  ),
                ],
              ),
            ),
          ),
        ),
        if (state.isDegraded) ...[
          const SizedBox(height: 12),
          Text(
            '一部の対象を封印できませんでした。Device Owner状態を確認して再試行してください。',
            key: const Key('lock-partial-failure-message'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (remoteReleaseFailure != null) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('lock-remote-release-error'),
            child: ListTile(
              leading: const Icon(Icons.sync_problem),
              title: Text(debtFailureMessage(remoteReleaseFailure!)),
              subtitle: const Text('負債の状態を再確認して、封印解除を再試行できます。'),
              trailing: TextButton(
                onPressed: onRetryRemoteRelease,
                child: const Text('再試行'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (active.isEmpty)
          const Text('未解決のlock obligationはありません。')
        else ...[
          const Text('解除条件: 各負債の完済、または表示期限への到達'),
          const SizedBox(height: 8),
          ...active.map(
            (obligation) => Card(
              key: Key('lock-obligation-${obligation.debtId}'),
              child: ListTile(
                title: Text('負債 ${_shortId(obligation.debtId)}'),
                subtitle: Text(
                  '封印 ${obligation.enforcedCount}/${obligation.targetCount}件'
                  '\n残り ${_remaining(obligation.expiresAt, now)}',
                ),
                trailing: obligation.localState == LockLocalState.degraded
                    ? const Icon(Icons.warning_amber)
                    : const Icon(Icons.lock),
              ),
            ),
          ),
          if (active.length > 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('複数の負債が同じアプリを対象にする場合、すべて解決するまで封印を維持します。'),
            ),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('lock-reconcile-button'),
          onPressed: onReconcile,
          icon: const Icon(Icons.sync),
          label: const Text('端末状態を再確認'),
        ),
      ],
    );
  }
}

final class _LockError extends StatelessWidget {
  const _LockError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, key: const Key('lock-status-error')),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}

String _shortId(String value) {
  return value.length <= 8 ? value : value.substring(0, 8);
}

String _remaining(DateTime expiresAt, DateTime now) {
  final duration = expiresAt.isAfter(now)
      ? expiresAt.difference(now)
      : Duration.zero;
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
