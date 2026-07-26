import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_failure.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('validates login fields before submitting', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpLogin(tester, repository);

    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(find.text('メールアドレスを入力してください。'), findsOneWidget);
    expect(find.text('パスワードを入力してください。'), findsOneWidget);
    expect(repository.signInCalls, isZero);
  });

  testWidgets('clears the password after a login submission', (tester) async {
    final repository = _FakeAuthRepository()
      ..signInCompleter = Completer<void>();
    await _pumpLogin(tester, repository);

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'valid-password',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pump();

    expect(repository.signInCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.signInCompleter!.complete();
    await tester.pumpAndSettle();

    final passwordField = tester.widget<TextFormField>(
      find.byKey(const Key('auth-password-field')),
    );
    expect(passwordField.controller!.text, isEmpty);
  });

  testWidgets('renders a typed auth failure without the SDK message', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..signInError = const AuthFailure(AuthFailureKind.invalidCredential);
    await _pumpLogin(tester, repository);

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'valid-password',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('メールアドレスまたはパスワードが正しくありません。'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}

Future<void> _pumpLogin(WidgetTester tester, _FakeAuthRepository repository) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
}

final class _FakeAuthRepository implements AuthRepository {
  final _authStateController = StreamController<AuthUser?>.broadcast();
  Completer<void>? signInCompleter;
  Object? signInError;
  int signInCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => _authStateController.stream;

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls += 1;
    if (signInError case final error?) {
      throw error;
    }
    await signInCompleter?.future;
  }

  @override
  Future<void> signOut() async {}
}
