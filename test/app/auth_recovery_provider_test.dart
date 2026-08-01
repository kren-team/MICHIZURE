import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/login_screen.dart';
import 'package:michizure/features/profile/domain/profile_repository.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';
import 'package:michizure/features/recovery/application/auth_revalidation_gate.dart';
import 'package:michizure/features/recovery/domain/recovery.dart';

void main() {
  test(
    'valid token gates profile listener until validation succeeds',
    () async {
      final validation = Completer<void>();
      final gateway = _FakeRecoveryAuthGateway(
        const RecoveryAuthResult(
          status: RecoveryAuthStatus.authenticated,
          userId: 'alice',
        ),
        blocker: validation,
      );
      final profiles = _FakeProfileRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _StaticAuthRepository(const AuthUser(id: 'alice')),
          ),
          recoveryAuthGatewayProvider.overrideWithValue(gateway),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(currentProfileProvider, (_, _) {});
      addTearDown(subscription.close);

      await Future<void>.delayed(Duration.zero);
      expect(gateway.calls, 1);
      expect(profiles.watchCalls, 0);

      validation.complete();
      await container.read(authStateProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(authStateProvider).value?.id, 'alice');
      expect(profiles.watchCalls, 1);
    },
  );

  test('temporary token failure does not sign out local auth', () async {
    final repository = _StaticAuthRepository(const AuthUser(id: 'alice'));
    final errorState = Completer<AsyncValue<AuthUser?>>();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        recoveryAuthGatewayProvider.overrideWithValue(
          _FakeRecoveryAuthGateway(
            const RecoveryAuthResult(
              status: RecoveryAuthStatus.temporarilyUnavailable,
              userId: 'alice',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(authStateProvider, (_, next) {
      if (next.hasError && !errorState.isCompleted) {
        errorState.complete(next);
      }
    });
    addTearDown(subscription.close);

    expect(
      (await errorState.future).error,
      isA<AuthSessionValidationFailure>(),
    );
    expect(repository.signOutCalls, 0);
  });

  testWidgets('permanent invalid credential converges router to Login', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _StaticAuthRepository(const AuthUser(id: 'alice')),
          ),
          recoveryAuthGatewayProvider.overrideWithValue(
            _FakeRecoveryAuthGateway(
              const RecoveryAuthResult(
                status: RecoveryAuthStatus.invalidCredentialSignedOut,
              ),
            ),
          ),
        ],
        child: const _RouterApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test(
    'Firestore unauthenticated signal is single-flight and sign-out disposes profile listener',
    () async {
      final auth = StreamController<AuthUser?>.broadcast();
      final profiles = _ControllableProfileRepository();
      final validation = Completer<void>();
      var validationCalls = 0;
      final gate = AuthRevalidationGate(() async {
        validationCalls += 1;
        await validation.future;
        auth.add(null);
      });
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => auth.stream),
          profileRepositoryProvider.overrideWithValue(profiles),
          authRevalidationGateProvider.overrideWithValue(gate),
        ],
      );
      final subscription = container.listen(currentProfileProvider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await auth.close();
        await profiles.close();
      });

      auth.add(const AuthUser(id: 'alice'));
      await _flushEvents();
      expect(profiles.watchCalls, 1);

      final error = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unauthenticated',
      );
      profiles.addError(error);
      profiles.addError(error);
      await _flushEvents();

      expect(validationCalls, 1);
      validation.complete();
      await _flushEvents();

      expect(container.read(authStateProvider).value, isNull);
      expect(profiles.cancelCalls, 1);
    },
  );
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _RouterApp extends ConsumerWidget {
  const _RouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(appRouterProvider));
  }
}

final class _StaticAuthRepository implements AuthRepository {
  _StaticAuthRepository(this.user);

  final AuthUser? user;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(user);

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
  }
}

final class _FakeRecoveryAuthGateway implements RecoveryAuthGateway {
  _FakeRecoveryAuthGateway(this.result, {this.blocker});

  final RecoveryAuthResult result;
  final Completer<void>? blocker;
  int calls = 0;

  @override
  Future<RecoveryAuthResult> recoverSession() async {
    calls += 1;
    await blocker?.future;
    return result;
  }
}

final class _FakeProfileRepository implements ProfileRepository {
  int watchCalls = 0;

  @override
  Stream<UserProfile?> watchProfile(String userId) {
    watchCalls += 1;
    return Stream.value(null);
  }

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {}
}

final class _ControllableProfileRepository implements ProfileRepository {
  _ControllableProfileRepository() {
    _controller = StreamController<UserProfile?>.broadcast(
      onCancel: () => cancelCalls += 1,
    );
  }

  late final StreamController<UserProfile?> _controller;
  int watchCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<UserProfile?> watchProfile(String userId) {
    watchCalls += 1;
    return _controller.stream;
  }

  void addError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {}
}
