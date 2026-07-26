import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import 'auth_failure_message.dart';
import 'login_screen.dart';
import 'widgets/auth_form.dart';

final class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final isSubmitting = state.isLoading;

    return AuthPage(
      title: 'アカウント作成',
      error: state.whenOrNull(
        error: (error, stackTrace) => authFailureMessage(error),
      ),
      form: AuthForm(
        submitLabel: '登録する',
        isSubmitting: isSubmitting,
        onSubmit: (email, password) => ref
            .read(authControllerProvider.notifier)
            .register(email: email, password: password),
      ),
      footer: TextButton(
        onPressed: isSubmitting
            ? null
            : () {
                ref.read(authControllerProvider.notifier).clearError();
                context.go('/login');
              },
        child: const Text('ログインへ戻る'),
      ),
    );
  }
}
