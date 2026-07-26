import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/register_screen.dart';

void main() {
  testWidgets('submits valid registration credentials', (tester) async {
    final repository = _RecordingAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'new@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'valid-password',
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();

    expect(repository.registerCalls, 1);
    expect(repository.lastEmail, 'new@example.test');
  });
}

final class _RecordingAuthRepository implements AuthRepository {
  int registerCalls = 0;
  String? lastEmail;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    registerCalls += 1;
    lastEmail = email;
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
