import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  test('interprets a restored signed-out state', () {
    final container = ProviderContainer(
      overrides: [authStateProvider.overrideWithValue(const AsyncData(null))],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appRouteStateProvider),
      const AsyncData(AuthRouteState.signedOut),
    );
  });

  test('interprets restored auth with a missing profile as Profile Setup', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(
          const AsyncData(AuthUser(id: 'alice')),
        ),
        currentProfileProvider.overrideWithValue(const AsyncData(null)),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appRouteStateProvider),
      const AsyncData(AuthRouteState.profileSetup),
    );
  });

  test('interprets restored auth and profile as ready', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWithValue(
          const AsyncData(AuthUser(id: 'alice')),
        ),
        currentProfileProvider.overrideWithValue(AsyncData(_profile)),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appRouteStateProvider),
      const AsyncData(AuthRouteState.ready),
    );
  });
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
