import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/core/time/clock.dart';
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

  testWidgets(
    'concurrent start selects one active Task and manual failure is idempotent',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final app = await Firebase.initializeApp(options: demoFirebaseOptions);
      final auth = FirebaseAuth.instanceFor(app: app);
      final firestore = FirebaseFirestore.instanceFor(app: app);
      await auth.useAuthEmulator(emulatorHost, authEmulatorPort);
      firestore.useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);

      final credential = await auth.createUserWithEmailAndPassword(
        email: 'task-$suffix@example.com',
        password: 'password123',
      );
      final uid = credential.user!.uid;
      await FirestoreProfileRepository(
        firestore,
      ).createProfile(userId: uid, displayName: '奏');
      final groupId = await FirestoreGroupRepository(
        firestore,
        SecureInviteTokenGenerator(),
        const SystemClock(),
      ).createGroup(userId: uid, displayName: '奏', name: '集中チーム');

      final repository = FirestoreTaskRepository(
        firestore,
        const SystemClock(),
      );
      final request = StartTaskRequest(
        ownerUid: uid,
        groupId: groupId,
        content: '論文を書く',
        durationSeconds: 60,
      );
      Future<TaskSession?> attemptStart() async {
        try {
          return await repository.startTask(request);
        } on Object {
          return null;
        }
      }

      final starts = await Future.wait([attemptStart(), attemptStart()]);
      final startedTasks = starts.whereType<TaskSession>().toList();
      expect(startedTasks, hasLength(1));
      final task = startedTasks.single;

      final userAfterStart = await firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      expect(userAfterStart.data()!['activeTaskSessionId'], task.id);

      const eventId = 'manual_integration_event';
      final failed = await repository.failTaskAndCreateDebt(
        ownerUid: uid,
        taskId: task.id,
        reason: TaskFailureReason.userAborted,
        failureEventId: eventId,
      );
      final duplicate = await repository.failTaskAndCreateDebt(
        ownerUid: uid,
        taskId: task.id,
        reason: TaskFailureReason.userAborted,
        failureEventId: eventId,
      );

      expect(failed.task.status, TaskSessionStatus.failed);
      expect(failed.debt.id, task.id);
      expect(failed.debt.totalReps, 10);
      expect(duplicate.debt.id, failed.debt.id);
      final userAfterFailure = await firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      expect(userAfterFailure.data()!['activeTaskSessionId'], isNull);
    },
  );
}
