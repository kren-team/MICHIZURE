import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/core/time/clock.dart';
import 'package:michizure/features/debt/infrastructure/firestore_debt_repository.dart';
import 'package:michizure/features/group/infrastructure/firestore_group_repository.dart';
import 'package:michizure/features/group/infrastructure/secure_invite_token_generator.dart';
import 'package:michizure/features/profile/infrastructure/firestore_profile_repository.dart';
import 'package:michizure/features/task/domain/task_repository.dart';
import 'package:michizure/features/task/domain/task_session.dart';
import 'package:michizure/features/task/infrastructure/firestore_task_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const emulatorHost = String.fromEnvironment(
    'MICHIZURE_FIREBASE_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  testWidgets('two group clients receive multiple Debts in real time', (
    tester,
  ) async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final appA = await Firebase.initializeApp(options: demoFirebaseOptions);
    final appB = await Firebase.initializeApp(
      name: 'debt-client-b-$suffix',
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
      email: 'debt-a-$suffix@example.com',
      password: 'password123',
    );
    final credentialB = await authB.createUserWithEmailAndPassword(
      email: 'debt-b-$suffix@example.com',
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

    final groupA = FirestoreGroupRepository(
      firestoreA,
      SecureInviteTokenGenerator(),
      const SystemClock(),
    );
    final groupB = FirestoreGroupRepository(
      firestoreB,
      SecureInviteTokenGenerator(),
      const SystemClock(),
    );
    final groupId = await groupA.createGroup(
      userId: uidA,
      displayName: '野々村 奏',
      name: 'Debt同期チーム',
    );
    final invite = await groupA.createInvite(userId: uidA, groupId: groupId);
    await groupB.joinGroup(
      userId: uidB,
      displayName: 'カナデ',
      rawInviteToken: invite.rawToken,
    );

    final debtsA = FirestoreDebtRepository(firestoreA);
    final debtsB = FirestoreDebtRepository(firestoreB);
    final taskRepository = FirestoreTaskRepository(
      firestoreA,
      const SystemClock(),
    );

    Future<void> failTask(String eventId) async {
      final task = await taskRepository.startTask(
        StartTaskRequest(
          ownerUid: uidA,
          groupId: groupId,
          content: '論文を書く',
          durationSeconds: 60,
        ),
      );
      await taskRepository.failTaskAndCreateDebt(
        ownerUid: uidA,
        taskId: task.id,
        reason: TaskFailureReason.userAborted,
        failureEventId: eventId,
      );
    }

    await failTask('debt_event_1_$suffix');
    final firstOnA = await debtsA
        .watchActiveDebts(groupId)
        .firstWhere((snapshot) => snapshot.value.length == 1);
    final firstOnB = await debtsB
        .watchActiveDebts(groupId)
        .firstWhere((snapshot) => snapshot.value.length == 1);
    expect(firstOnA.value.single.totalReps, 20);
    expect(firstOnB.value.single.id, firstOnA.value.single.id);

    await failTask('debt_event_2_$suffix');
    final secondOnA = await debtsA
        .watchActiveDebts(groupId)
        .firstWhere((snapshot) => snapshot.value.length == 2);
    final secondOnB = await debtsB
        .watchActiveDebts(groupId)
        .firstWhere((snapshot) => snapshot.value.length == 2);
    expect(secondOnA.value.map((debt) => debt.id).toSet(), hasLength(2));
    expect(
      secondOnB.value.map((debt) => debt.failedUserId),
      everyElement(uidA),
    );
  });
}
