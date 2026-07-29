import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/contribution_controller.dart';
import '../domain/contribution.dart';
import '../domain/debt.dart';
import 'debt_failure_message.dart';

final class ContributionSessionScreen extends ConsumerWidget {
  const ContributionSessionScreen({required this.debtId, super.key});

  final String debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debt = ref.watch(debtProvider(debtId));
    final syncState = ref.watch(contributionControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('返済するDebt')),
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
            isFromCache: snapshot.isFromCache,
            hasPendingWrites: snapshot.hasPendingWrites,
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
    this.onRetry,
    super.key,
  });

  final Debt debt;
  final ContributionControllerState state;
  final bool isFromCache;
  final bool hasPendingWrites;
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
        const Divider(height: 32),
        Text('端末内の判定状態', style: Theme.of(context).textTheme.titleMedium),
        Text('検出 ${state.detectedCount} 回'),
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
        const Divider(height: 32),
        const Text(
          'スクワットは次のPhaseで端末内カメラ判定します。'
          'この画面から回数を手入力することはできません。',
          key: Key('contribution-no-manual-input'),
        ),
      ],
    );
  }
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
