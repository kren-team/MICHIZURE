import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../application/group_controller.dart';
import 'group_failure_message.dart';

final class GroupJoinScreen extends ConsumerStatefulWidget {
  const GroupJoinScreen({super.key});

  @override
  ConsumerState<GroupJoinScreen> createState() => _GroupJoinScreenState();
}

final class _GroupJoinScreenState extends ConsumerState<GroupJoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentProfileProvider, (previous, next) {
      if (previous?.value?.groupId == null && next.value?.groupId != null) {
        context.go('/home');
      }
    });
    final profile = ref.watch(currentProfileProvider).value;
    final command = ref.watch(groupControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('グループに参加')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('group-invite-token-field'),
                    controller: _tokenController,
                    enabled: !command.isLoading,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: '招待コード'),
                    validator: (value) => (value?.trim().isNotEmpty ?? false)
                        ? null
                        : '招待コードを入力してください。',
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
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('group-join-button'),
                    onPressed: command.isLoading || profile == null
                        ? null
                        : () => _submit(profile.id, profile.displayName),
                    child: command.isLoading
                        ? const CircularProgressIndicator()
                        : const Text('参加する'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String userId, String displayName) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await ref
        .read(groupControllerProvider.notifier)
        .joinGroup(
          userId: userId,
          displayName: displayName,
          rawInviteToken: _tokenController.text,
        );
  }
}
