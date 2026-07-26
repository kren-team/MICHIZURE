import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/application/auth_controller.dart';
import 'package:michizure/features/auth/domain/auth_repository.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';

void main() {
  test('register is single-flight', () async {
    final repository = _ControllableAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);
    final first = controller.register(
      email: 'user@example.test',
      password: 'valid-password',
    );
    final second = controller.register(
      email: 'user@example.test',
      password: 'valid-password',
    );

    expect(repository.registerCalls, 1);
    repository.completer.complete();
    await Future.wait([first, second]);
    expect(container.read(authControllerProvider), const AsyncData<void>(null));
  });

  test('signIn is single-flight', () async {
    final repository = _ControllableAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);
    final first = controller.signIn(
      email: 'user@example.test',
      password: 'valid-password',
    );
    final second = controller.signIn(
      email: 'user@example.test',
      password: 'valid-password',
    );

    expect(repository.signInCalls, 1);
    repository.completer.complete();
    await Future.wait([first, second]);
  });

  test('signOut is single-flight', () async {
    final repository = _ControllableAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider.notifier);
    final first = controller.signOut();
    final second = controller.signOut();

    expect(repository.signOutCalls, 1);
    repository.completer.complete();
    await Future.wait([first, second]);
  });
}

final class _ControllableAuthRepository implements AuthRepository {
  final completer = Completer<void>();
  int registerCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    registerCalls += 1;
    await completer.future;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls += 1;
    await completer.future;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    await completer.future;
  }
}
