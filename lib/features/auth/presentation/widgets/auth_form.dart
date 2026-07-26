import 'package:flutter/material.dart';

import '../../domain/auth_form_validator.dart';

final class AuthForm extends StatefulWidget {
  const AuthForm({
    required this.submitLabel,
    required this.onSubmit,
    required this.isSubmitting,
    super.key,
  });

  final String submitLabel;
  final Future<void> Function(String email, String password) onSubmit;
  final bool isSubmitting;

  @override
  State<AuthForm> createState() => _AuthFormState();
}

final class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('auth-email-field'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            enabled: !widget.isSubmitting,
            decoration: const InputDecoration(labelText: 'メールアドレス'),
            validator: (value) =>
                _emailErrorMessage(AuthFormValidator.email(value ?? '')),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('auth-password-field'),
            controller: _passwordController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [AutofillHints.password],
            enabled: !widget.isSubmitting,
            decoration: const InputDecoration(labelText: 'パスワード（8文字以上）'),
            validator: (value) =>
                _passwordErrorMessage(AuthFormValidator.password(value ?? '')),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('auth-submit-button'),
            onPressed: widget.isSubmitting ? null : _submit,
            child: widget.isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final email = _emailController.text;
    final password = _passwordController.text;
    await widget.onSubmit(email, password);
    _passwordController.clear();
  }
}

String? _emailErrorMessage(AuthFieldError? error) {
  return switch (error) {
    null => null,
    AuthFieldError.required => 'メールアドレスを入力してください。',
    AuthFieldError.invalidEmail => 'メールアドレスの形式を確認してください。',
    _ => null,
  };
}

String? _passwordErrorMessage(AuthFieldError? error) {
  return switch (error) {
    null => null,
    AuthFieldError.required => 'パスワードを入力してください。',
    AuthFieldError.passwordTooShort => 'パスワードは8文字以上にしてください。',
    AuthFieldError.passwordTooLong => 'パスワードは128文字以下にしてください。',
    _ => null,
  };
}
