import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/profile_controller.dart';
import '../domain/profile_failure.dart';
import '../domain/user_profile.dart';

final class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

final class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(profileControllerProvider);
    final user = ref.watch(authStateProvider).value;
    final isSaving = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール設定')),
      body: SafeArea(
        child: Center(
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
                    const Text('グループに表示する名前を設定してください。'),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('profile-display-name-field'),
                      controller: _displayNameController,
                      enabled: !isSaving,
                      decoration: const InputDecoration(labelText: '表示名'),
                      validator: (value) =>
                          ProfileValidator.isValidDisplayName(value ?? '')
                          ? null
                          : '表示名は1〜40文字で入力してください。',
                    ),
                    if (state.whenOrNull(error: (error, stackTrace) => error)
                        case final error?) ...[
                      const SizedBox(height: 12),
                      Text(
                        _profileFailureMessage(error),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('profile-save-button'),
                      onPressed: isSaving || user == null ? null : _save,
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存する'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      return;
    }
    await ref
        .read(profileControllerProvider.notifier)
        .createProfile(
          userId: user.id,
          displayName: _displayNameController.text,
        );
  }
}

String _profileFailureMessage(Object error) {
  if (error is ProfileFailure &&
      error.kind == ProfileFailureKind.invalidDisplayName) {
    return '表示名は1〜40文字で入力してください。';
  }
  return 'プロフィールを保存できませんでした。再試行してください。';
}
