import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../application/auth_controller.dart';

final class AuthenticatedPlaceholderScreen extends ConsumerWidget {
  const AuthenticatedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final profile = ref.watch(currentProfileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MICHIZURE'),
        actions: [
          IconButton(
            tooltip: 'プロフィール',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.person_outline),
          ),
          TextButton(
            onPressed: authState.isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${profile?.displayName ?? ''} さん、グループ機能は次のPhaseで実装します。'),
        ),
      ),
    );
  }
}
