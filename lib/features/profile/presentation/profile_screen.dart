import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/profile_controller.dart';
import '../domain/user_profile.dart';

final class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

final class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final user = ref.watch(authStateProvider).value;
    final state = ref.watch(profileControllerProvider);
    final isSaving = state.isLoading;

    if (profile == null || user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadedProfileId != profile.id) {
      _displayNameController.text = profile.displayName;
      _loadedProfileId = profile.id;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('profile-display-name-field'),
                controller: _displayNameController,
                enabled: !isSaving,
                maxLength: ProfileValidator.maximumDisplayNameLength,
                decoration: const InputDecoration(labelText: '表示名'),
                validator: (value) =>
                    ProfileValidator.isValidDisplayName(value ?? '')
                    ? null
                    : '表示名は制御文字を含めず、1〜40文字で入力してください。',
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('profile-save-button'),
                onPressed: isSaving ? null : () => _save(user.id),
                child: const Text('変更を保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(String userId) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await ref
        .read(profileControllerProvider.notifier)
        .updateDisplayName(
          userId: userId,
          displayName: _displayNameController.text,
        );
  }
}
