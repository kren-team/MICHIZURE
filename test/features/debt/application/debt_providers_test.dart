import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/profile/domain/profile_repository.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

import '../support/fake_debt_repository.dart';

void main() {
  test('group change and logout detach the old Debt listener', () async {
    late final StreamController<AuthUser?> auth;
    auth = StreamController<AuthUser?>.broadcast(
      onListen: () {
        scheduleMicrotask(() => auth.add(const AuthUser(id: 'alice')));
      },
    );
    final profiles = _ProfileRepository(_profile('group-1'));
    final debts = FakeDebtRepository();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        profileRepositoryProvider.overrideWithValue(profiles),
        debtRepositoryProvider.overrideWithValue(debts),
      ],
    );
    final subscription = container.listen(
      activeGroupDebtsProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      container.dispose();
      await auth.close();
      await profiles.dispose();
      await debts.dispose();
    });

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(debts.watchedGroupIds, ['group-1']);
    expect(debts.activeController.hasListener, isTrue);

    profiles.controller.add(_profile('group-2'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(debts.watchedGroupIds, ['group-1', 'group-2']);

    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(activeGroupDebtsProvider).value?.value, isEmpty);

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(debts.activeController.hasListener, isFalse);
  });
}

final class _ProfileRepository implements ProfileRepository {
  _ProfileRepository(UserProfile initial) {
    controller = StreamController<UserProfile?>.broadcast(
      onListen: () => scheduleMicrotask(() => controller.add(initial)),
    );
  }

  late final StreamController<UserProfile?> controller;

  @override
  Stream<UserProfile?> watchProfile(String userId) => controller.stream;

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) {
    throw UnimplementedError();
  }

  Future<void> dispose() => controller.close();
}

UserProfile _profile(String groupId) {
  return UserProfile(
    id: 'alice',
    displayName: '奏',
    photoUrl: null,
    groupId: groupId,
    activeTaskSessionId: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
