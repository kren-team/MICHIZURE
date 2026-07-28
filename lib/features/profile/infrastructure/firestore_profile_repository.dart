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
      final userReference = _users.doc(userId);
      await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userReference);
        if (!userSnapshot.exists) {
          throw const ProfileFailure(ProfileFailureKind.invalidData);
        }
        final groupId = userSnapshot.data()!['groupId'];
        if (groupId != null && groupId is! String) {
          throw const ProfileFailure(ProfileFailureKind.invalidData);
        }

        DocumentReference<Map<String, dynamic>>? memberReference;
        if (groupId is String) {
          memberReference = _firestore
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(userId);
          final memberSnapshot = await transaction.get(memberReference);
          if (!memberSnapshot.exists) {
            throw const ProfileFailure(ProfileFailureKind.invalidData);
          }
        }

        transaction.update(userReference, {
          'displayName': normalizedName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (memberReference != null) {
          transaction.update(memberReference, {
            'displayNameSnapshot': normalizedName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
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
