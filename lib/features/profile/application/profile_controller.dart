import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/profile_repository.dart';

final profileControllerProvider =
    NotifierProvider<ProfileController, AsyncValue<void>>(
      ProfileController.new,
    );

final class ProfileController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  ProfileRepository get _repository => ref.read(profileRepositoryProvider);

  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) {
    return _submit(
      () => _repository.createProfile(userId: userId, displayName: displayName),
    );
  }

  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) {
    return _submit(
      () => _repository.updateDisplayName(
        userId: userId,
        displayName: displayName,
      ),
    );
  }

  Future<void> _submit(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}
