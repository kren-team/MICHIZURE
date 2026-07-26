import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/profile_failure.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

final class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Stream<UserProfile?> watchProfile(String userId) {
    return _users.doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return userProfileFromFirestore(userId, snapshot.data()!);
    });
  }

  @override
  Future<void> createProfile({
    required String userId,
    required String displayName,
  }) async {
    final normalizedName = ProfileValidator.normalizeDisplayName(displayName);
    if (!ProfileValidator.isValidDisplayName(normalizedName)) {
      throw const ProfileFailure(ProfileFailureKind.invalidDisplayName);
    }

    try {
      await _users.doc(userId).set({
        'displayName': normalizedName,
        'photoUrl': null,
        'groupId': null,
        'activeTaskSessionId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'schemaVersion': UserProfile.schemaVersion,
      });
    } on FirebaseException {
      throw const ProfileFailure(ProfileFailureKind.unknown);
    }
  }

  @override
  Future<void> updateDisplayName({
    required String userId,
    required String displayName,
  }) async {
    final normalizedName = ProfileValidator.normalizeDisplayName(displayName);
    if (!ProfileValidator.isValidDisplayName(normalizedName)) {
      throw const ProfileFailure(ProfileFailureKind.invalidDisplayName);
    }

    try {
      await _users.doc(userId).update({
        'displayName': normalizedName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      throw const ProfileFailure(ProfileFailureKind.unknown);
    }
  }
}

UserProfile userProfileFromFirestore(String userId, Map<String, dynamic> data) {
  final displayName = data['displayName'];
  final photoUrl = data['photoUrl'];
  final groupId = data['groupId'];
  final activeTaskSessionId = data['activeTaskSessionId'];
  final createdAt = data['createdAt'];
  final updatedAt = data['updatedAt'];
  final schemaVersion = data['schemaVersion'];

  if (displayName is! String ||
      !ProfileValidator.isValidDisplayName(displayName) ||
      ProfileValidator.normalizeDisplayName(displayName) != displayName ||
      (photoUrl != null && photoUrl is! String) ||
      (groupId != null && groupId is! String) ||
      (activeTaskSessionId != null && activeTaskSessionId is! String) ||
      createdAt is! Timestamp ||
      updatedAt is! Timestamp ||
      schemaVersion != UserProfile.schemaVersion) {
    throw const ProfileFailure(ProfileFailureKind.invalidData);
  }

  return UserProfile(
    id: userId,
    displayName: displayName,
    photoUrl: photoUrl as String?,
    groupId: groupId as String?,
    activeTaskSessionId: activeTaskSessionId as String?,
    createdAt: createdAt.toDate(),
    updatedAt: updatedAt.toDate(),
  );
}
