import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/auth/domain/auth_failure.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/login_screen.dart';
import 'package:michizure/features/auth/presentation/register_screen.dart';

void main() {
  testWidgets('Login error is cleared when navigating to Register', (
    tester,
  ) async {
    final repository = _FailingAuthRepository();
    await _pumpSignedOutRouter(tester, repository);

    await _submitAuthForm(tester);
    expect(find.byKey(const Key('auth-error-message')), findsOneWidget);

    await tester.tap(find.text('アカウントを作成する'));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.byKey(const Key('auth-error-message')), findsNothing);
  });

  testWidgets('Register error is cleared when navigating to Login', (
    tester,
  ) async {
    final repository = _FailingAuthRepository();
    await _pumpSignedOutRouter(tester, repository);
    await tester.tap(find.text('アカウントを作成する'));
    await tester.pumpAndSettle();

    await _submitAuthForm(tester);
    expect(repository.registerCalls, 1);
    expect(find.byKey(const Key('auth-error-message')), findsOneWidget);

    await tester.tap(find.text('ログインへ戻る'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('auth-error-message')), findsNothing);
  });
}

Future<void> _pumpSignedOutRouter(
  WidgetTester tester,
  AuthRepository repository,
) async {
  final gate = AuthRouteGate();
  gate.update(const AsyncData(AuthRouteState.signedOut));
  final router = createAppRouter(authRouteGate: gate);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitAuthForm(WidgetTester tester) async {
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
}

final class _FailingAuthRepository implements AuthRepository {
  int registerCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(null);

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    registerCalls += 1;
    throw const AuthFailure(AuthFailureKind.emailAlreadyInUse);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    throw const AuthFailure(AuthFailureKind.invalidCredential);
  }

  @override
  Future<void> signOut() async {}
}
