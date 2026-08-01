import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/presentation/app_components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../group/domain/group_member.dart';
import '../application/debt_expiration_controller.dart';
import '../domain/debt.dart';
import 'debt_failure_message.dart';

final class DebtListScreen extends ConsumerStatefulWidget {
  const DebtListScreen({super.key});

  @override
  ConsumerState<DebtListScreen> createState() => _DebtListScreenState();
}

final class _DebtListScreenState extends ConsumerState<DebtListScreen> {
  Timer? _expirationTicker;

  @override
  void initState() {
    super.initState();
    _expirationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final snapshot = ref.read(activeGroupDebtsProvider).value;
      if (snapshot != null) {
        unawaited(
          ref
              .read(debtExpirationControllerProvider.notifier)
              .expireOverdue(snapshot.value, ref.read(clockProvider).now()),
        );
      }
    });
  }

  @override
  void dispose() {
    _expirationTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final debts = ref.watch(activeGroupDebtsProvider);
    final members = ref.watch(currentGroupMembersProvider);
    final expiration = ref.watch(debtExpirationControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('現在の負債'),
        actions: const [MichizureHomeAction()],
      ),
      body: profile?.groupId == null
          ? const _CenteredMessage(
              key: Key('debt-group-required'),
              message: 'グループに参加すると負債を確認できます。',
            )
          : debts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _DebtLoadError(
                message: debtFailureMessage(error),
                onRetry: () => ref.invalidate(activeGroupDebtsProvider),
              ),
              data: (snapshot) {
                final memberValues = members.value ?? const <GroupMember>[];
                return _DebtList(
                  snapshot: snapshot,
                  members: memberValues,
                  expirationFailure: expiration.whenOrNull(
                    error: (error, stackTrace) => error,
                  ),
                );
              },
            ),
    );
  }
}

final class _DebtList extends StatelessWidget {
  const _DebtList({
    required this.snapshot,
    required this.members,
    required this.expirationFailure,
  });

  final DebtSnapshot<List<Debt>> snapshot;
  final List<GroupMember> members;
  final Object? expirationFailure;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in members) member.userId: member.displayName,
    };
    return ListView(
      padding: const EdgeInsets.all(MichizureSpacing.page),
      children: [
        if (snapshot.isFromCache)
          const Card(
            key: Key('debt-cache-banner'),
            child: ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('オフラインの保存済みデータを表示中'),
              subtitle: Text('接続すると自動で最新状態へ同期します。'),
            ),
          ),
        if (snapshot.hasPendingWrites)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('サーバーへの反映を待っています。'),
          ),
        if (expirationFailure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              debtFailureMessage(expirationFailure!),
              key: const Key('debt-expiration-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (snapshot.value.isEmpty)
          const _CenteredMessage(
            key: Key('debt-empty-state'),
            message: '現在返済が必要な負債はありません。\n新しい約束を始められます。',
          )
        else
          ...snapshot.value.map(
            (debt) => Padding(
              padding: const EdgeInsets.only(bottom: MichizureSpacing.item),
              child: Card(
                key: Key('debt-card-${debt.id}'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(MichizureRadii.card),
                  onTap: () => context.go('/debts/${debt.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(MichizureSpacing.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.fitness_center),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                names[debt.failedUserId] ?? 'グループメンバー',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '残り ${debt.remainingReps} 回 / ${debt.totalReps} 回',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: MichizureColors.pink,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '発生 ${_formatDateTime(debt.createdAt)}'
                          '  ・  期限 ${_formatDateTime(debt.lockExpiresAt)}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _DebtLoadError extends StatelessWidget {
  const _DebtLoadError({required this.message, required this.onRetry});

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
            Text(message, key: const Key('debt-list-error')),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}

final class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MichizureEmptyState(
      message: message,
      icon: Icons.fitness_center_outlined,
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
