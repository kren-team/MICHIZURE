import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/group_controller.dart';
import 'group_failure_message.dart';

final class GroupInviteScreen extends ConsumerWidget {
  const GroupInviteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;
    final command = ref.watch(groupControllerProvider);
    final issuedInvite = command.value;

    return Scaffold(
      appBar: AppBar(title: const Text('グループ招待')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('招待コードは24時間有効です。コードを知っているユーザーは40人まで参加できます。'),
                const SizedBox(height: 20),
                if (issuedInvite case final invite?) ...[
                  SelectableText(
                    invite.rawToken,
                    key: const Key('group-issued-token'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('有効期限: ${invite.invite.expiresAt.toLocal()}'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: invite.rawToken),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('招待コードをコピーしました')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('コピー'),
                  ),
                  TextButton(
                    key: const Key('group-revoke-invite-button'),
                    onPressed: command.isLoading || profile == null
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('招待を取り消しますか？'),
                                content: const Text('このコードでは新しく参加できなくなります。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('キャンセル'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('取り消す'),
                                  ),
                                ],
                              ),
                            );
                            if ((confirmed ?? false) && context.mounted) {
                              await ref
                                  .read(groupControllerProvider.notifier)
                                  .revokeInvite(
                                    userId: profile.id,
                                    tokenHash: invite.invite.tokenHash,
                                  );
                            }
                          },
                    child: const Text('この招待を取り消す'),
                  ),
                ] else
                  FilledButton(
                    key: const Key('group-create-invite-button'),
                    onPressed:
                        command.isLoading ||
                            profile == null ||
                            profile.groupId == null
                        ? null
                        : () => ref
                              .read(groupControllerProvider.notifier)
                              .createInvite(
                                userId: profile.id,
                                groupId: profile.groupId!,
                              ),
                    child: command.isLoading
                        ? const CircularProgressIndicator()
                        : const Text('招待コードを発行'),
                  ),
                if (command.whenOrNull(error: (error, stackTrace) => error)
                    case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    groupFailureMessage(error),
                    key: const Key('group-error-message'),
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
