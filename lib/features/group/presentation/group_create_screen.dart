import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../application/group_controller.dart';
import '../domain/group.dart';
import 'group_failure_message.dart';

final class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

final class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
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
      appBar: AppBar(title: const Text('グループを作成')),
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
                    key: const Key('group-name-field'),
                    controller: _nameController,
                    enabled: !command.isLoading,
                    maxLength: GroupNameValidator.maximumLength,
                    decoration: const InputDecoration(labelText: 'グループ名'),
                    validator: (value) =>
                        GroupNameValidator.isValid(value ?? '')
                        ? null
                        : 'グループ名は制御文字を含めず、1〜50文字で入力してください。',
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
                    key: const Key('group-create-button'),
                    onPressed: command.isLoading || profile == null
                        ? null
                        : () => _submit(profile.id, profile.displayName),
                    child: command.isLoading
                        ? const CircularProgressIndicator()
                        : const Text('作成する'),
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
        .createGroup(
          userId: userId,
          displayName: displayName,
          name: _nameController.text,
        );
  }
}
