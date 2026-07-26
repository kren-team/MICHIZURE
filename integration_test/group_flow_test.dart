import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/core/time/clock.dart';
import 'package:michizure/features/group/domain/group_member.dart';
import 'package:michizure/features/group/infrastructure/firestore_group_repository.dart';
import 'package:michizure/features/group/infrastructure/secure_invite_token_generator.dart';
import 'package:michizure/features/profile/infrastructure/firestore_profile_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emulatorHost = String.fromEnvironment(
    'MICHIZURE_FIREBASE_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  testWidgets(
    'two clients create, join, observe members in real time, and leave',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final appA = await Firebase.initializeApp(
        options: demoFirebaseOptions,
      );
      final appB = await Firebase.initializeApp(
        name: 'group-client-b-$suffix',
        options: demoFirebaseOptions,
      );
      addTearDown(appB.delete);

      final authA = FirebaseAuth.instanceFor(app: appA);
      final authB = FirebaseAuth.instanceFor(app: appB);
      final firestoreA = FirebaseFirestore.instanceFor(app: appA);
      final firestoreB = FirebaseFirestore.instanceFor(app: appB);
      await authA.useAuthEmulator(emulatorHost, authEmulatorPort);
      await authB.useAuthEmulator(emulatorHost, authEmulatorPort);
      firestoreA.useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);
      firestoreB.useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);

      final credentialA = await authA.createUserWithEmailAndPassword(
        email: 'group-a-$suffix@example.com',
        password: 'password123',
      );
      final credentialB = await authB.createUserWithEmailAndPassword(
        email: 'group-b-$suffix@example.com',
        password: 'password123',
      );
      final uidA = credentialA.user!.uid;
      final uidB = credentialB.user!.uid;

      await FirestoreProfileRepository(
        firestoreA,
      ).createProfile(userId: uidA, displayName: '野々村 奏');
      await FirestoreProfileRepository(
        firestoreB,
      ).createProfile(userId: uidB, displayName: 'カナデ');

      final repositoryA = FirestoreGroupRepository(
        firestoreA,
        SecureInviteTokenGenerator(),
        const SystemClock(),
      );
      final repositoryB = FirestoreGroupRepository(
        firestoreB,
        SecureInviteTokenGenerator(),
        const SystemClock(),
      );

      final groupId = await repositoryA.createGroup(
        userId: uidA,
        displayName: '野々村 奏',
        name: '朝活チーム',
      );
      final invite = await repositoryA.createInvite(
        userId: uidA,
        groupId: groupId,
      );

      final ownerOnly = await repositoryA
          .watchMembers(groupId)
          .firstWhere((members) => members.length == 1);
      expect(ownerOnly.single.role, GroupMemberRole.owner);

      await repositoryB.joinGroup(
        userId: uidB,
        displayName: 'カナデ',
        rawInviteToken: invite.rawToken,
      );

      final membersSeenByA = await repositoryA
          .watchMembers(groupId)
          .firstWhere((members) => members.length == 2);
      final membersSeenByB = await repositoryB
          .watchMembers(groupId)
          .firstWhere((members) => members.length == 2);
      expect(
        membersSeenByA.map((member) => member.displayName),
        containsAll(<String>['野々村 奏', 'カナデ']),
      );
      expect(
        membersSeenByB.map((member) => member.userId),
        containsAll(<String>[uidA, uidB]),
      );

      await repositoryB.leaveGroup(userId: uidB, groupId: groupId);

      final remainingSeenByA = await repositoryA
          .watchMembers(groupId)
          .firstWhere((members) => members.length == 1);
      expect(remainingSeenByA.single.userId, uidA);
      expect(
        await firestoreB
            .collection('users')
            .doc(uidB)
            .get()
            .then((snapshot) => snapshot.data()!['groupId']),
        isNull,
      );
    },
  );
}
