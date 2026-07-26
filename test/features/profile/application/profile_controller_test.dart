import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/profile/application/profile_controller.dart';
import 'package:michizure/features/profile/domain/profile_repository.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  test('createProfile is single-flight', () async {
    final repository = _ControllableProfileRepository();
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileControllerProvider.notifier);
    final first = controller.createProfile(
      userId: 'alice',
      displayName: 'Alice',
    );
    final second = controller.createProfile(
      userId: 'alice',
      displayName: 'Alice',
    );

    expect(repository.createCalls, 1);
    repository.completer.complete();
    await Future.wait([first, second]);
  });

  test('updateDisplayName is single-flight', () async {
    final repository = _ControllableProfileRepository();
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileControllerProvider.notifier);
    final first = controller.updateDisplayName(
      userId: 'alice',
      displayName: 'Renamed',
    );
    final second = controller.updateDisplayName(
      userId: 'alice',
      displayName: 'Renamed',
    );

    expect(repository.updateCalls, 1);
    repository.completer.complete();
    await Future.wait([first, second]);
  });
}

final class _ControllableProfileRepository implements ProfileRepository {
  final completer = Completer<void>();
  int createCalls = 0;
  int updateCalls = 0;

  @override
  Stream<UserProfile?> watchProfile(String userId) => const Stream.empty();

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {
    createCalls += 1;
    await completer.future;
  }

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    updateCalls += 1;
    await completer.future;
  }
}
