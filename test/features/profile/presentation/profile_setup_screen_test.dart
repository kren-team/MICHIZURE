import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/profile/domain/profile_repository.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';
import 'package:michizure/features/profile/presentation/profile_setup_screen.dart';

void main() {
  testWidgets('creates a profile with a valid Unicode display name', (
    tester,
  ) async {
    final repository = _RecordingProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(id: 'alice')),
          ),
        ],
        child: const MaterialApp(home: ProfileSetupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      '野々村 奏',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(repository.lastDisplayName, '野々村 奏');
  });
}

final class _RecordingProfileRepository implements ProfileRepository {
  int createCalls = 0;
  String? lastDisplayName;

  @override
  Stream<UserProfile?> watchProfile(String userId) => Stream.value(null);

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {
    createCalls += 1;
    lastDisplayName = displayName;
  }

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {}
}
