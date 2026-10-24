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
    final textTheme = Theme.of(context).textTheme;
    final debtorName = names[debt.failedUserId] ?? 'グループメンバー';
    final isActive = debt.status == DebtStatus.active;
    final statusColor = switch (debt.status) {
      DebtStatus.active => MichizureColors.accent,
      DebtStatus.completed => MichizureColors.success,
      DebtStatus.expired => MichizureColors.textSecondary,
    };
    final list = ListView(
      padding: const EdgeInsets.all(MichizureSpacing.page),
      children: [
        if (isFromCache)
          const Padding(
            padding: EdgeInsets.only(bottom: MichizureSpacing.item),
            child: MichizureStatusPill(
              key: Key('debt-detail-cache-banner'),
              label: 'オフラインの保存済みデータです',
              icon: Icons.cloud_off,
              color: MichizureColors.warning,
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(MichizureSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MichizureAvatar(name: debtorName, highlighted: isActive),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(debtorName, style: textTheme.titleMedium),
                          Text('が約束を破りました', style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                    MichizureStatusPill(
                      label: _statusLabel(debt.status),
                      icon: switch (debt.status) {
                        DebtStatus.active => Icons.directions_run,
                        DebtStatus.completed => Icons.check_circle_outline,
                        DebtStatus.expired => Icons.timer_off_outlined,
                      },
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                MichizureRepCount(
                  reps: debt.remainingReps,
                  textKey: const Key('debt-detail-remaining'),
                  fontSize: 48,
                  color: statusColor,
                ),
                const SizedBox(height: 14),
                MichizureProgressBar(
                  value: debt.totalReps == 0
                      ? 0
                      : debt.completedReps / debt.totalReps,
                  color: statusColor,
                ),
                const SizedBox(height: 10),
                Text(
                  '合計 ${debt.totalReps} 回 / 完了 ${debt.completedReps} 回',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: MichizureSpacing.item),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MichizureSpacing.card,
              vertical: 6,
            ),
            child: Column(
              children: [
                _InfoRow(label: '発生', value: _formatDateTime(debt.createdAt)),
                const Divider(height: 1),
                _InfoRow(
                  label: '封印期限',
                  value: _formatDateTime(debt.lockExpiresAt),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            '完済または期限到達で、この負債によるアプリ封印が解除されます。',
            style: TextStyle(fontSize: 12, color: MichizureColors.textTertiary),
          ),
        ),
        const MichizureSectionHeader(title: 'メンバー別の返済'),
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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(MichizureSpacing.card),
              child: Text(
                'まだ確定した返済はありません。',
                key: Key('debt-contributions-empty'),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(
                children: [
                  for (final summary in summaries!)
                    ListTile(
                      key: Key('debt-contribution-${summary.userId}'),
                      leading: MichizureAvatar(
                        name: names[summary.userId] ?? '?',
                      ),
                      title: Text(names[summary.userId] ?? 'グループメンバー'),
                      trailing: Text(
                        '${summary.totalReps} 回',
                        style: textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
    if (!isActive) return list;
    return Column(
      children: [
        Expanded(child: list),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MichizureSpacing.page,
              8,
              MichizureSpacing.page,
              12,
            ),
            child: SizedBox(
              width: double.infinity,
              child: MichizurePrimaryButton(
                buttonKey: const Key('debt-repay-action'),
                accent: true,
                onPressed: () => context.go('/debts/${debt.id}/repay'),
                icon: const Icon(Icons.directions_run),
                child: const Text('この負債を返済する'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
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
