import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/auth_failure_message.dart';
import '../application/group_controller.dart';
import '../domain/group.dart';
import '../domain/group_member.dart';
import 'group_failure_message.dart';

final class GroupHomeScreen extends ConsumerWidget {
  const GroupHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const Text('仲間とスクワット負債を返済するグループを作成するか、招待コードで参加してください。'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('group-create-route-button'),
                  onPressed: () {
                    ref.read(groupControllerProvider.notifier).clearResult();
                    context.go('/group/create');
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text('グループを作成'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('グループ'),
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
  ) {
    final isOwner = group.ownerUid == userId;
    final transferCandidates = members
        .where((member) => member.userId != userId)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('${group.memberCount} / ${Group.maximumMemberCount} 人'),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('group-invite-route-button'),
          onPressed: command.isLoading
              ? null
              : () => context.go('/group/invite'),
          icon: const Icon(Icons.share),
          label: const Text('招待コードを発行'),
        ),
        const SizedBox(height: 24),
        Text('メンバー', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...members.map(
          (member) => ListTile(
            key: Key('group-member-${member.userId}'),
            leading: Icon(
              member.role == GroupMemberRole.owner
                  ? Icons.workspace_premium
                  : Icons.person,
            ),
            title: Text(member.displayName),
            trailing: Text(
              member.role == GroupMemberRole.owner ? '所有者' : 'メンバー',
            ),
          ),
        ),
        if (isOwner && transferCandidates.isNotEmpty) ...[
          const Divider(height: 32),
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
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('group-leave-button'),
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

List<Widget> _accountActions(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<void> authCommand,
) {
  return [
    IconButton(
      key: const Key('device-setup-route-button'),
      tooltip: '端末セットアップ',
      onPressed: () => context.go('/device-setup'),
      icon: const Icon(Icons.phonelink_setup),
    ),
    IconButton(
      tooltip: 'プロフィール',
      onPressed: () => context.go('/profile'),
      icon: const Icon(Icons.person_outline),
    ),
    TextButton(
      onPressed: authCommand.isLoading
          ? null
          : () => ref.read(authControllerProvider.notifier).signOut(),
      child: const Text('ログアウト'),
    ),
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
