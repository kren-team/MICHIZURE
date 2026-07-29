import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../group/domain/group_member.dart';
import '../domain/debt.dart';
import 'debt_failure_message.dart';

final class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({required this.debtId, super.key});

  final String debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debt = ref.watch(debtProvider(debtId));
    final contributions = ref.watch(debtContributionsProvider(debtId));
    final members = ref.watch(currentGroupMembersProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Debt詳細')),
      body: debt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _DetailError(
          message: debtFailureMessage(error),
          onRetry: () {
            ref.invalidate(debtProvider(debtId));
            ref.invalidate(debtContributionsProvider(debtId));
          },
        ),
        data: (snapshot) {
          final value = snapshot.value;
          if (value == null) {
            return const Center(child: Text('Debtが見つかりません。'));
          }
          return contributions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _DetailError(
              message: debtFailureMessage(error),
              onRetry: () => ref.invalidate(debtContributionsProvider(debtId)),
            ),
            data: (summarySnapshot) => _DebtDetail(
              debt: value,
              summaries: summarySnapshot.value,
              members: members ?? const [],
              isFromCache: snapshot.isFromCache || summarySnapshot.isFromCache,
            ),
          );
        },
      ),
    );
  }
}

final class _DebtDetail extends StatelessWidget {
  const _DebtDetail({
    required this.debt,
    required this.summaries,
    required this.members,
    required this.isFromCache,
  });

  final Debt debt;
  final List<DebtContributionSummary> summaries;
  final List<GroupMember> members;
  final bool isFromCache;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in members) member.userId: member.displayName,
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (isFromCache)
          const Text('オフラインの保存済みデータです。', key: Key('debt-detail-cache-banner')),
        Text(
          names[debt.failedUserId] ?? 'グループメンバー',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          '残り ${debt.remainingReps} 回',
          key: const Key('debt-detail-remaining'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('合計 ${debt.totalReps} 回 / 完了 ${debt.completedReps} 回'),
        Text('状態: ${_statusLabel(debt.status)}'),
        const Divider(height: 32),
        Text('メンバー別の確定回数', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (summaries.isEmpty)
          const Text('まだ確定した返済はありません。', key: Key('debt-contributions-empty'))
        else
          ...summaries.map(
            (summary) => ListTile(
              key: Key('debt-contribution-${summary.userId}'),
              leading: const Icon(Icons.person),
              title: Text(names[summary.userId] ?? 'グループメンバー'),
              trailing: Text('${summary.totalReps} 回'),
            ),
          ),
        const SizedBox(height: 16),
        const Text('返済操作は次のPhaseで追加します。'),
      ],
    );
  }
}

final class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, key: const Key('debt-detail-error')),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ),
    );
  }
}

String _statusLabel(DebtStatus status) {
  return switch (status) {
    DebtStatus.active => '返済中',
    DebtStatus.completed => '完済',
    DebtStatus.expired => '期限終了',
  };
}
