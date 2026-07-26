import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import 'auth_failure_message.dart';
import 'widgets/auth_form.dart';

final class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);
    final isSubmitting = state.isLoading;

    return AuthPage(
      title: 'ログイン',
      error: state.whenOrNull(
        error: (error, stackTrace) => authFailureMessage(error),
      ),
      form: AuthForm(
        submitLabel: 'ログイン',
        isSubmitting: isSubmitting,
        onSubmit: (email, password) => ref
            .read(authControllerProvider.notifier)
            .signIn(email: email, password: password),
      ),
      footer: TextButton(
        onPressed: isSubmitting
            ? null
            : () {
                ref.read(authControllerProvider.notifier).clearError();
                context.go('/register');
              },
        child: const Text('アカウントを作成する'),
      ),
    );
  }
}

final class AuthPage extends StatelessWidget {
  const AuthPage({
    required this.title,
    required this.error,
    required this.form,
    required this.footer,
    super.key,
  });

  final String title;
  final String? error;
  final Widget form;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error case final message?) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        key: const Key('auth-error-message'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  form,
                  const SizedBox(height: 8),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
