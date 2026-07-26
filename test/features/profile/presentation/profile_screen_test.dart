import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/profile/domain/profile_failure.dart';
import 'package:michizure/features/profile/domain/profile_repository.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';
import 'package:michizure/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('shows confirmation after a successful profile update', (
    tester,
  ) async {
    final repository = _FakeProfileRepository();
    await _pumpProfile(tester, repository);

    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      '  野々村 奏  ',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.lastDisplayName, '  野々村 奏  ');
    expect(find.text('プロフィールを保存しました。'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('profile-display-name-field')),
    );
    expect(field.controller!.text, '野々村 奏');
  });

  testWidgets('shows a safe message after a failed profile update', (
    tester,
  ) async {
    final repository = _FakeProfileRepository()
      ..updateError = const ProfileFailure(ProfileFailureKind.unknown);
    await _pumpProfile(tester, repository);

    await tester.enterText(
      find.byKey(const Key('profile-display-name-field')),
      'Renamed',
    );
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(find.byKey(const Key('profile-error-message')), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.text('プロフィールを保存しました。'), findsNothing);

    repository.updateError = null;
    await tester.tap(find.byKey(const Key('profile-save-button')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 2);
    expect(find.byKey(const Key('profile-error-message')), findsNothing);
    expect(find.text('プロフィールを保存しました。'), findsOneWidget);
  });
}

Future<void> _pumpProfile(
  WidgetTester tester,
  ProfileRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'alice')),
        ),
        currentProfileProvider.overrideWith((ref) => Stream.value(_profile)),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

final class _FakeProfileRepository implements ProfileRepository {
  Object? updateError;
  int updateCalls = 0;
  String? lastDisplayName;

  @override
  Stream<UserProfile?> watchProfile(String userId) => Stream.value(_profile);

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    updateCalls += 1;
    lastDisplayName = displayName;
    if (updateError case final error?) {
      throw error;
    }
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
