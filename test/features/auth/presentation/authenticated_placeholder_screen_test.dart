import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_failure.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/authenticated_placeholder_screen.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  testWidgets('shows a safe typed failure when logout fails', (tester) async {
    final repository = _FailingSignOutRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          currentProfileProvider.overrideWith((ref) => Stream.value(_profile)),
        ],
        child: const MaterialApp(home: AuthenticatedPlaceholderScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ログアウト'));
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(find.byKey(const Key('logout-error-message')), findsOneWidget);
    expect(find.text('ネットワークに接続できません。接続を確認してください。'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}

final class _FailingSignOutRepository implements AuthRepository {
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(const AuthUser(id: 'alice'));

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    throw const AuthFailure(AuthFailureKind.networkUnavailable);
  }
}

final _profile = UserProfile(
  id: 'alice',
  displayName: 'Alice',
  photoUrl: null,
  groupId: null,
  activeTaskSessionId: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
