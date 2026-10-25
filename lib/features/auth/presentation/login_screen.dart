import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/app_theme.dart';
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
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: MichizureSpacing.page,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 64,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandMark(),
                      const SizedBox(height: 48),
                      Text(title, style: textTheme.headlineSmall),
                      const SizedBox(height: 20),
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
        ),
      ),
    );
  }
}

final class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: MichizureColors.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'MICHIZURE',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            height: 1,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '約束を破ったら、仲間もスクワット。',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: MichizureColors.textSecondary),
        ),
      ],
    );
  }
}
