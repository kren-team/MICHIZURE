import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/auth_repository.dart';

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);

final class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> register({required String email, required String password}) {
    return _submit(
      () => _repository.register(email: email, password: password),
    );
  }

  Future<void> signIn({required String email, required String password}) {
    return _submit(() => _repository.signIn(email: email, password: password));
  }

  Future<void> signOut() => _submit(_repository.signOut);

  void clearError() {
    if (state.hasError) {
      state = const AsyncData(null);
    }
  }

  Future<void> _submit(Future<void> Function() action) async {
    if (state.isLoading) {
      return;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    if (ref.mounted) {
      state = result;
    }
  }
}
