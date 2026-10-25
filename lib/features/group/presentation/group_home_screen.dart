import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/presentation/app_components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/auth_failure_message.dart';
import '../../debt/application/debt_lock_release_controller.dart';
import '../../debt/domain/debt.dart';
import '../../enforcement/application/device_setup_controller.dart';
import '../../enforcement/presentation/selected_apps_summary.dart';
import '../../home/domain/home_guidance.dart';
import '../application/group_controller.dart';
import '../domain/group.dart';
import '../domain/group_member.dart';
import 'group_failure_message.dart';

final class GroupHomeScreen extends ConsumerWidget {
  const GroupHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(debtLockReleaseControllerProvider);
    final profile = ref.watch(currentProfileProvider).value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (profile.groupId == null) {
      return const _GroupOnboardingView();
    }
    return const _GroupDashboardView();
  }
}

final class _GroupOnboardingView extends ConsumerWidget {
  const _GroupOnboardingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authCommand = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MICHIZURE'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
        actions: _accountActions(context, ref, authCommand),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'まずは、道連れにする\n仲間を集めよう。',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  '誰かが約束を破ると、グループ全員にスクワット負債が発生します。'
                  'グループを作るか、仲間から届いた招待コードで参加してください。',
                ),
                const SizedBox(height: 32),
                MichizurePrimaryButton(
                  buttonKey: const Key('group-create-route-button'),
                  onPressed: () {
                    ref.read(groupControllerProvider.notifier).clearResult();
                    context.go('/group/create');
                  },
                  icon: const Icon(Icons.group_add),
                  child: const Text('グループを作成'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('group-join-route-button'),
                  onPressed: () {
                    ref.read(groupControllerProvider.notifier).clearResult();
                    context.go('/group/join');
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('招待コードで参加'),
                ),
                if (authCommand.whenOrNull(error: (error, stackTrace) => error)
                    case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    authFailureMessage(error),
                    key: const Key('logout-error-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _GroupDashboardView extends ConsumerStatefulWidget {
  const _GroupDashboardView();

  @override
  ConsumerState<_GroupDashboardView> createState() =>
      _GroupDashboardViewState();
}

final class _GroupDashboardViewState
    extends ConsumerState<_GroupDashboardView> {
  String? _selectedNewOwnerUid;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value!;
    final authUser = ref.watch(authStateProvider).value;
    final groupState = ref.watch(currentGroupProvider);
    final membersState = ref.watch(currentGroupMembersProvider);
    final command = ref.watch(groupControllerProvider);
    final authCommand = ref.watch(authControllerProvider);
    final debtsState = ref.watch(activeGroupDebtsProvider);
    final deviceSetup = ref.watch(deviceSetupControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(groupState.value?.name ?? 'グループ'),
        actions: _accountActions(context, ref, authCommand),
      ),
      body: groupState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _GroupLoadError(
          onRetry: () {
            ref.invalidate(currentGroupProvider);
            ref.invalidate(currentGroupMembersProvider);
          },
        ),
        data: (group) {
          if (group == null || authUser == null) {
            return const _GroupLoadError();
          }
          return membersState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _GroupLoadError(
              onRetry: () => ref.invalidate(currentGroupMembersProvider),
            ),
            data: (members) => _buildDashboard(
              context,
              group,
              members,
              authUser.id,
              profile.displayName,
              command,
              debtsState,
              deviceSetup,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    Group group,
    List<GroupMember> members,
    String userId,
    String displayName,
    AsyncValue<Object?> command,
    AsyncValue<DebtSnapshot<List<Debt>>> debtsState,
    AsyncValue<DeviceSetupState> deviceSetup,
  ) {
    final isOwner = group.ownerUid == userId;
    final transferCandidates = members
        .where((member) => member.userId != userId)
        .toList(growable: false);
    final setup = deviceSetup.value;
    final guidance = HomeGuidance.derive(
      deviceSetupLoaded: setup != null,
      deviceSetupReady: setup?.capabilities.isManagedDemoReady ?? false,
      selectedAppCount: setup?.savedPackageNames.length ?? 0,
      activeDebtCount: debtsState.value?.value.length ?? 0,
    );

    final activeDebts = debtsState.value?.value ?? const <Debt>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MichizureSpacing.page,
        4,
        MichizureSpacing.page,
        40,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            '${profileGreeting(displayName)}、おかえりなさい',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: MichizureColors.textSecondary,
            ),
          ),
        ),
        _NextActionCard(
          guidance: guidance,
          activeDebts: activeDebts,
          onPressed: command.isLoading
              ? null
              : () => _openNextAction(context, guidance.action),
        ),
        const SizedBox(height: MichizureSpacing.item),
        _QuickActionGrid(
          children: [
            _QuickActionTile(
              tileKey: const Key('task-composer-route-button'),
              icon: Icons.timer_outlined,
              label: '約束を始める',
              caption: '集中する時間を決める',
              onTap: command.isLoading ? null : () => context.go('/task/new'),
            ),
            _QuickActionTile(
              tileKey: const Key('debt-list-route-button'),
              icon: Icons.fitness_center,
              label: '負債',
              caption: debtsState.when(
                loading: () => '読み込み中',
                error: (error, stackTrace) => '読み込みエラー',
                data: (snapshot) => snapshot.value.isEmpty
                    ? 'なし'
                    : '${snapshot.value.length}件・返済中',
              ),
              highlighted: activeDebts.isNotEmpty,
              onTap: () => context.go('/debts'),
            ),
            _QuickActionTile(
              tileKey: const Key('lock-status-route-button'),
              icon: Icons.lock_outline,
              label: '封印状態',
              caption: '封印中のアプリ',
              onTap: () => context.go('/lock-status'),
            ),
            _QuickActionTile(
              tileKey: const Key('group-invite-route-button'),
              icon: Icons.person_add_alt,
              label: '仲間を招待',
              caption: '招待コードを発行',
              onTap: command.isLoading
                  ? null
                  : () => context.go('/group/invite'),
            ),
          ],
        ),
        if (setup != null) ...[
          const MichizureSectionHeader(title: '封印するアプリ'),
          Card(
            key: const Key('home-selected-apps-card'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: SelectedAppsSummary(
                apps: setup.apps,
                selectedPackageNames: setup.savedPackageNames,
                manageButtonKey: const Key('home-app-selection-button'),
                onManage: () => context.go('/device-setup/apps'),
              ),
            ),
          ),
        ],
        MichizureSectionHeader(
          title: 'メンバー',
          trailing: Text(
            '${group.memberCount} / ${Group.maximumMemberCount}',
            style: MichizureTextStyles.overline,
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                for (final member in members)
                  ListTile(
                    key: Key('group-member-${member.userId}'),
                    leading: MichizureAvatar(
                      name: member.displayName,
                      highlighted: activeDebts.any(
                        (debt) => debt.failedUserId == member.userId,
                      ),
                    ),
                    title: Text(
                      member.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: switch (_memberSubtitle(member, activeDebts)) {
                      final text? => Text(text),
                      null => null,
                    },
                    trailing: member.role == GroupMemberRole.owner
                        ? const MichizureStatusPill(
                            label: '所有者',
                            icon: Icons.workspace_premium_outlined,
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
        const MichizureSectionHeader(title: 'グループ管理'),
        if (isOwner && transferCandidates.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: const Key('group-owner-transfer-select'),
            initialValue: _selectedNewOwnerUid,
            decoration: const InputDecoration(labelText: '新しい所有者'),
            items: transferCandidates
                .map(
                  (member) => DropdownMenuItem(
                    value: member.userId,
                    child: Text(member.displayName),
                  ),
                )
                .toList(growable: false),
            onChanged: command.isLoading
                ? null
                : (value) => setState(() => _selectedNewOwnerUid = value),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('group-transfer-owner-button'),
            onPressed: command.isLoading || _selectedNewOwnerUid == null
                ? null
                : () => ref
                      .read(groupControllerProvider.notifier)
                      .transferOwnership(
                        userId: userId,
                        groupId: group.id,
                        newOwnerUid: _selectedNewOwnerUid!,
                      ),
            child: const Text('所有者を移譲'),
          ),
        ],
        if (command.whenOrNull(error: (error, stackTrace) => error)
            case final error?) ...[
          const SizedBox(height: 16),
          Text(
            groupFailureMessage(error),
            key: const Key('group-error-message'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(
          key: const Key('group-leave-button'),
          style: TextButton.styleFrom(foregroundColor: MichizureColors.error),
          onPressed: command.isLoading
              ? null
              : () => _confirmLeave(
                  context,
                  userId: userId,
                  groupId: group.id,
                  isOwner: isOwner,
                ),
          child: Text(isOwner ? 'グループを退出（移譲が必要）' : 'グループを退出'),
        ),
      ],
    );
  }

  void _openNextAction(BuildContext context, HomeNextAction action) {
    switch (action) {
      case HomeNextAction.completeDeviceSetup:
        context.go('/device-setup');
        return;
      case HomeNextAction.selectLockApps:
        context.go('/device-setup/apps');
        return;
      case HomeNextAction.viewDebts:
        context.go('/debts');
        return;
      case HomeNextAction.startTask:
        context.go('/task/new');
        return;
    }
  }

  Future<void> _confirmLeave(
    BuildContext context, {
    required String userId,
    required String groupId,
    required bool isOwner,
  }) async {
    if (isOwner) {
      await showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text('所有者は退出できません'),
          content: Text('先に所有者を他のメンバーへ移譲してください。最後のメンバーは退出できません。'),
        ),
      );
      return;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('グループを退出しますか？'),
        content: const Text('退出するとこのグループの共有情報を閲覧できなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (shouldLeave ?? false) {
      await ref
          .read(groupControllerProvider.notifier)
          .leaveGroup(userId: userId, groupId: groupId);
    }
  }
}

String profileGreeting(String displayName) =>
    displayName.trim().isEmpty ? 'こんにちは' : '$displayNameさん';

String? _memberSubtitle(GroupMember member, List<Debt> activeDebts) {
  final remaining = activeDebts
      .where((debt) => debt.failedUserId == member.userId)
      .fold<int>(0, (sum, debt) => sum + debt.remainingReps);
  return remaining == 0 ? null : '負債 残り$remaining回';
}

final class _NextActionCard extends StatelessWidget {
  const _NextActionCard({
    required this.guidance,
    required this.activeDebts,
    required this.onPressed,
  });

  final HomeGuidance guidance;
  final List<Debt> activeDebts;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final showsDebt = guidance.action == HomeNextAction.viewDebts;
    final remaining = activeDebts.fold<int>(
      0,
      (sum, debt) => sum + debt.remainingReps,
    );
    final total = activeDebts.fold<int>(0, (sum, debt) => sum + debt.totalReps);
    return Card(
      key: const Key('home-next-action-card'),
      child: Padding(
        padding: const EdgeInsets.all(MichizureSpacing.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: showsDebt
                        ? MichizureColors.accent
                        : MichizureColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('次にすること', style: MichizureTextStyles.overline),
              ],
            ),
            const SizedBox(height: 14),
            if (showsDebt && total > 0) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$remaining',
                    key: const Key('home-debt-remaining'),
                    style: MichizureTextStyles.counter.copyWith(
                      color: MichizureColors.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '回 残っています',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MichizureProgressBar(value: 1 - remaining / total),
              const SizedBox(height: 14),
            ],
            Text(
              guidance.title,
              key: const Key('home-next-action-title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(guidance.description),
            const SizedBox(height: 20),
            MichizurePrimaryButton(
              buttonKey: const Key('home-next-action-button'),
              onPressed: onPressed,
              accent: showsDebt,
              icon: Icon(_actionIcon(guidance.action)),
              child: Text(guidance.actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _actionIcon(HomeNextAction action) {
  return switch (action) {
    HomeNextAction.completeDeviceSetup => Icons.phonelink_setup,
    HomeNextAction.selectLockApps => Icons.apps,
    HomeNextAction.viewDebts => Icons.directions_run,
    HomeNextAction.startTask => Icons.timer_outlined,
  };
}

final class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index += 2) {
      if (index > 0) {
        rows.add(const SizedBox(height: MichizureSpacing.item));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[index]),
              const SizedBox(width: MichizureSpacing.item),
              Expanded(
                child: index + 1 < children.length
                    ? children[index + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

final class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
    this.highlighted = false,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: highlighted
                    ? MichizureColors.accent
                    : enabled
                    ? MichizureColors.textPrimary
                    : MichizureColors.textTertiary,
              ),
              const SizedBox(height: 18),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: enabled ? null : MichizureColors.textTertiary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: highlighted ? MichizureColors.accent : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AccountMenuItem { profile, signOut }

List<Widget> _accountActions(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<void> authCommand,
) {
  return [
    if (kDebugMode)
      IconButton(
        key: const Key('debug-squat-lab-route-button'),
        tooltip: 'Squat Lab（Debug）',
        onPressed: () => context.go('/debug/squat-lab'),
        icon: const Icon(Icons.science_outlined),
      ),
    IconButton(
      key: const Key('device-setup-route-button'),
      tooltip: '端末セットアップ',
      onPressed: () => context.go('/device-setup'),
      icon: const Icon(Icons.phonelink_setup),
    ),
    PopupMenuButton<_AccountMenuItem>(
      key: const Key('account-menu-button'),
      tooltip: 'アカウント',
      icon: const Icon(Icons.more_vert),
      onSelected: (item) {
        switch (item) {
          case _AccountMenuItem.profile:
            context.go('/profile');
          case _AccountMenuItem.signOut:
            if (!authCommand.isLoading) {
              ref.read(authControllerProvider.notifier).signOut();
            }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AccountMenuItem.profile,
          child: ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('プロフィール'),
          ),
        ),
        PopupMenuItem(
          value: _AccountMenuItem.signOut,
          enabled: !authCommand.isLoading,
          child: const ListTile(
            leading: Icon(Icons.logout),
            title: Text('ログアウト'),
          ),
        ),
      ],
    ),
    const SizedBox(width: 4),
  ];
}

final class _GroupLoadError extends StatelessWidget {
  const _GroupLoadError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('グループ情報を読み込めませんでした。'),
          if (onRetry case final retry?) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: retry, child: const Text('再試行')),
          ],
        ],
      ),
    );
  }
}
