import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

final class AuthenticatedPlaceholderScreen extends ConsumerWidget {
  const AuthenticatedPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MICHIZURE'),
        actions: [
          TextButton(
            onPressed: authState.isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('ログアウト'),
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('認証済みです。プロフィール設定を確認しています。'),
        ),
      ),
    );
  }
}
