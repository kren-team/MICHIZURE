import 'user_profile.dart';

abstract interface class ProfileRepository {
  Stream<UserProfile?> watchProfile(String userId);

  Future<void> createProfile({
    required String userId,
    required String displayName,
  });

  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  });
}
