import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/presentation/app_components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../group/domain/group_member.dart';
import '../domain/debt.dart';
import 'debt_failure_message.dart';

final class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({required this.debtId, this.initialDebt, super.key});

  final String debtId;
  final Debt? initialDebt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debt = ref.watch(debtProvider(debtId));
    final contributions = ref.watch(debtContributionsProvider(debtId));
    final members = ref.watch(currentGroupMembersProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('負債の詳細'),
        actions: const [MichizureHomeAction()],
      ),
      body: debt.when(
        loading: () => initialDebt == null
            ? const Center(child: CircularProgressIndicator())
            : _buildDetail(
                ref,
                debt: initialDebt!,
                contributions: contributions,
                members: members,
                debtIsFromCache: false,
              ),
        error: (error, stackTrace) => _DetailError(
          message: debtFailureMessage(error),
          onRetry: () {
            ref.invalidate(debtProvider(debtId));
            ref.invalidate(debtContributionsProvider(debtId));
          },
        ),
        data: (snapshot) {
          final value =
              snapshot.value ?? (snapshot.isFromCache ? initialDebt : null);
          if (value == null) {
            if (snapshot.isFromCache) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('負債が見つかりません。'));
          }
          return _buildDetail(
            ref,
            debt: value,
            contributions: contributions,
            members: members,
            debtIsFromCache: snapshot.value != null && snapshot.isFromCache,
          );
        },
      ),
    );
  }

  Widget _buildDetail(
    WidgetRef ref, {
    required Debt debt,
    required AsyncValue<DebtSnapshot<List<DebtContributionSummary>>>
    contributions,
    required List<GroupMember>? members,
    required bool debtIsFromCache,
  }) {
    final summarySnapshot = contributions.value;
    final contributionError = contributions.whenOrNull(
      error: (error, stackTrace) => debtFailureMessage(error),
    );
    return _DebtDetail(
      debt: debt,
      summaries: summarySnapshot?.value,
      contributionError: contributionError,
      onRetryContributions: () =>
          ref.invalidate(debtContributionsProvider(debtId)),
      members: members ?? const [],
      isFromCache: debtIsFromCache || (summarySnapshot?.isFromCache ?? false),
    );
  }
}

final class _DebtDetail extends StatelessWidget {
  const _DebtDetail({
    required this.debt,
    required this.summaries,
    required this.contributionError,
    required this.onRetryContributions,
    required this.members,
    required this.isFromCache,
  });

  final Debt debt;
  final List<DebtContributionSummary>? summaries;
  final String? contributionError;
  final VoidCallback onRetryContributions;
  final List<GroupMember> members;
  final bool isFromCache;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in members) member.userId: member.displayName,
    };
    return ListView(
      padding: const EdgeInsets.all(MichizureSpacing.page),
      children: [
        if (isFromCache)
          const Text('オフラインの保存済みデータです。', key: Key('debt-detail-cache-banner')),
        MichizureMetricCard(
          label: names[debt.failedUserId] ?? 'グループメンバー',
          value: '残り ${debt.remainingReps} 回',
          valueKey: const Key('debt-detail-remaining'),
          icon: Icons.fitness_center,
          description: '合計 ${debt.totalReps} 回 / 完了 ${debt.completedReps} 回',
          child: MichizureStatusPill(
            label: _statusLabel(debt.status),
            icon: debt.status == DebtStatus.active
                ? Icons.sync
                : Icons.check_circle_outline,
            color: debt.status == DebtStatus.active
                ? MichizureColors.pink
                : MichizureColors.success,
          ),
        ),
        const SizedBox(height: 12),
        Text('状態: ${_statusLabel(debt.status)}'),
        Text('発生: ${_formatDateTime(debt.createdAt)}'),
        Text('封印期限: ${_formatDateTime(debt.lockExpiresAt)}'),
        const SizedBox(height: 8),
        const Text('完済または期限到達で、この負債によるアプリ封印が解除されます。'),
        const Divider(height: 32),
        Text('メンバー別の確定回数', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (contributionError != null) ...[
          Text(
            contributionError!,
            key: const Key('debt-contributions-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: onRetryContributions, child: const Text('再試行')),
        ] else if (summaries == null)
          const LinearProgressIndicator(key: Key('debt-contributions-loading'))
        else if (summaries!.isEmpty)
          const Text('まだ確定した返済はありません。', key: Key('debt-contributions-empty'))
        else
          ...summaries!.map(
            (summary) => ListTile(
              key: Key('debt-contribution-${summary.userId}'),
              leading: const Icon(Icons.person),
              title: Text(names[summary.userId] ?? 'グループメンバー'),
              trailing: Text('${summary.totalReps} 回'),
            ),
          ),
        const SizedBox(height: 16),
        if (debt.status == DebtStatus.active)
          MichizurePrimaryButton(
            buttonKey: const Key('debt-repay-action'),
            onPressed: () => context.go('/debts/${debt.id}/repay'),
            icon: const Icon(Icons.directions_run),
            child: const Text('この負債を返済する'),
          ),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
