import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/auth/infrastructure/firebase_auth_repository.dart';
import '../features/enforcement/domain/device_control_repository.dart';
import '../features/enforcement/infrastructure/device_control_channel.dart';
import '../features/group/domain/group.dart';
import '../features/group/domain/group_invite.dart';
import '../features/group/domain/group_member.dart';
import '../features/group/domain/group_repository.dart';
import '../features/group/infrastructure/firestore_group_repository.dart';
import '../features/group/infrastructure/secure_invite_token_generator.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/infrastructure/firestore_profile_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final deviceControlRepositoryProvider = Provider<DeviceControlRepository>((
  ref,
) {
  return MethodChannelDeviceControlRepository();
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return FirestoreProfileRepository(ref.watch(firebaseFirestoreProvider));
});

final currentProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return Stream.value(null);
  }
  return ref.watch(profileRepositoryProvider).watchProfile(user.id);
});

final inviteTokenGeneratorProvider = Provider<InviteTokenGenerator>((ref) {
  return SecureInviteTokenGenerator();
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(inviteTokenGeneratorProvider),
  );
});

final currentGroupProvider = StreamProvider<Group?>((ref) {
  final groupId = ref.watch(currentProfileProvider).value?.groupId;
  if (groupId == null) {
    return Stream.value(null);
  }
  return ref.watch(groupRepositoryProvider).watchGroup(groupId);
});

final currentGroupMembersProvider = StreamProvider<List<GroupMember>>((ref) {
  final groupId = ref.watch(currentProfileProvider).value?.groupId;
  if (groupId == null) {
    return Stream.value(const []);
  }
  return ref.watch(groupRepositoryProvider).watchMembers(groupId);
});
