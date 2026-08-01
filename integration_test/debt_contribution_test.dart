import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/core/time/clock.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/infrastructure/firestore_contribution_repository.dart';
import 'package:michizure/features/debt/infrastructure/firestore_debt_repository.dart';
import 'package:michizure/features/debt/infrastructure/shared_preferences_contribution_outbox.dart';
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
    'three group clients contribute atomically and receive completion',
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final clientA = await _createClient(
        name: null,
        email: 'contribution-a-$suffix@example.com',
        displayName: '野々村 奏',
        emulatorHost: emulatorHost,
      );
      final additionalClients = await Future.wait([
        _createClient(
          name: 'contribution-client-b-$suffix',
          email: 'contribution-b-$suffix@example.com',
          displayName: 'カナデ',
          emulatorHost: emulatorHost,
        ),
        _createClient(
          name: 'contribution-client-c-$suffix',
          email: 'contribution-c-$suffix@example.com',
          displayName: 'Kanade 野々村',
          emulatorHost: emulatorHost,
        ),
      ]);
      final clientB = additionalClients[0];
      final clientC = additionalClients[1];
      final clients = [clientA, clientB, clientC];
      addTearDown(() async {
        await clientB.app.delete();
        await clientC.app.delete();
      });

      final groupA = clientA.groupRepository;
      final groupId = await groupA.createGroup(
        userId: clientA.uid,
        displayName: clientA.displayName,
        name: 'Contribution同期チーム',
      );
      final invite = await groupA.createInvite(
        userId: clientA.uid,
        groupId: groupId,
      );
      await clientB.groupRepository.joinGroup(
        userId: clientB.uid,
        displayName: clientB.displayName,
        rawInviteToken: invite.rawToken,
      );
      await clientC.groupRepository.joinGroup(
        userId: clientC.uid,
        displayName: clientC.displayName,
        rawInviteToken: invite.rawToken,
      );

      final taskRepository = FirestoreTaskRepository(
        clientA.firestore,
        const SystemClock(),
      );
      final task = await taskRepository.startTask(
        StartTaskRequest(
          ownerUid: clientA.uid,
          groupId: groupId,
          content: '数学の課題',
          durationSeconds: 60,
        ),
      );
      final failed = await taskRepository.failTaskAndCreateDebt(
        ownerUid: clientA.uid,
        taskId: task.id,
        reason: TaskFailureReason.userAborted,
        failureEventId: 'contribution_failure_$suffix',
      );
      final debtId = failed.debt.id;
      expect(failed.debt.totalReps, 30);

      final debtRepositories = clients
          .map((client) => FirestoreDebtRepository(client.firestore))
          .toList(growable: false);
      final completedFutures = debtRepositories
          .map(
            (repository) => repository
                .watchDebt(debtId)
                .firstWhere(
                  (snapshot) => snapshot.value?.status.name == 'completed',
                ),
          )
          .toList(growable: false);
      final summaryFutures = debtRepositories
          .map(
            (repository) => repository
                .watchContributions(debtId)
                .firstWhere(
                  (snapshot) =>
                      snapshot.value.fold<int>(
                        0,
                        (total, summary) => total + summary.totalReps,
                      ) ==
                      30,
                ),
          )
          .toList(growable: false);

      final repositories = clients
          .map(
            (client) => FirestoreContributionRepository(
              client.firestore,
              const SystemClock(),
            ),
          )
          .toList(growable: false);
      final sequences = <String, int>{
        clientA.uid: 0,
        clientB.uid: 0,
        clientC.uid: 0,
      };
      ContributionRequest nextRequest(int clientIndex) {
        final client = clients[clientIndex];
        final sequence = (sequences[client.uid] ?? 0) + 1;
        sequences[client.uid] = sequence;
        return _request(debtId: debtId, userId: client.uid, sequence: sequence);
      }

      final firstA = nextRequest(0);
      final firstB = nextRequest(1);
      final firstResults = await Future.wait([
        repositories[0].submit(firstA),
        repositories[1].submit(firstB),
      ]);
      expect(
        firstResults.map((result) => result.acceptedReps),
        everyElement(1),
      );

      final duplicate = await repositories[0].submit(firstA);
      expect(duplicate.isDuplicate, isTrue);
      expect(duplicate.acceptedReps, 0);

      for (var index = 0; index < 27; index += 1) {
        final clientIndex = index % clients.length;
        final result = await repositories[clientIndex].submit(
          nextRequest(clientIndex),
        );
        expect(result.acceptedReps, 1);
      }

      Future<Object> finalAttempt(int clientIndex) async {
        try {
          return await repositories[clientIndex].submit(
            nextRequest(clientIndex),
          );
        } on ContributionFailure catch (failure) {
          return failure;
        }
      }

      final finalRace = await Future.wait([finalAttempt(0), finalAttempt(1)]);
      expect(finalRace.whereType<ContributionCommitResult>(), hasLength(1));
      final rejected = finalRace.whereType<ContributionFailure>().single;
      expect(
        rejected.reason,
        anyOf(
          ContributionRejectionReason.debtTerminal,
          ContributionRejectionReason.debtFull,
        ),
      );

      final completedSnapshots = await Future.wait(completedFutures);
      expect(
        completedSnapshots.map((snapshot) => snapshot.value!.completedReps),
        everyElement(30),
      );
      final summarySnapshots = await Future.wait(summaryFutures);
      for (final snapshot in summarySnapshots) {
        expect(snapshot.value, hasLength(3));
        expect(
          snapshot.value.fold<int>(
            0,
            (total, summary) => total + summary.totalReps,
          ),
          30,
        );
      }
    },
  );

  testWidgets('local outbox survives adapter recreation', (tester) async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final userId = 'outbox-user-$suffix';
    final request = _request(
      debtId: 'outbox-debt-$suffix',
      userId: userId,
      sequence: 1,
    );
    final first = SharedPreferencesContributionOutbox();
    await first.put(request);

    final restored = await SharedPreferencesContributionOutbox().loadForUser(
      userId,
    );
    expect(restored.map((entry) => entry.eventId), [request.eventId]);

    await SharedPreferencesContributionOutbox().remove(request.eventId);
    expect(
      await SharedPreferencesContributionOutbox().loadForUser(userId),
      isEmpty,
    );
  });
}

final class _Client {
  const _Client({
    required this.app,
    required this.firestore,
    required this.uid,
    required this.displayName,
    required this.groupRepository,
  });

  final FirebaseApp app;
  final FirebaseFirestore firestore;
  final String uid;
  final String displayName;
  final FirestoreGroupRepository groupRepository;
}

Future<_Client> _createClient({
  required String? name,
  required String email,
  required String displayName,
  required String emulatorHost,
}) async {
  final app = await Firebase.initializeApp(
    name: name,
    options: demoFirebaseOptions,
  );
  final auth = FirebaseAuth.instanceFor(app: app);
  final firestore = FirebaseFirestore.instanceFor(app: app);
  await auth.useAuthEmulator(emulatorHost, authEmulatorPort);
  firestore.useFirestoreEmulator(emulatorHost, firestoreEmulatorPort);
  final credential = await auth.createUserWithEmailAndPassword(
    email: email,
    password: 'password123',
  );
  final uid = credential.user!.uid;
  await FirestoreProfileRepository(
    firestore,
  ).createProfile(userId: uid, displayName: displayName);
  return _Client(
    app: app,
    firestore: firestore,
    uid: uid,
    displayName: displayName,
    groupRepository: FirestoreGroupRepository(
      firestore,
      SecureInviteTokenGenerator(),
      const SystemClock(),
    ),
  );
}

ContributionRequest _request({
  required String debtId,
  required String userId,
  required int sequence,
}) {
  const sessionId = 'integration-1234';
  return ContributionRequest(
    debtId: debtId,
    userId: userId,
    eventId: ContributionEventId.build(
      userId: userId,
      squatSessionId: sessionId,
      sequence: sequence,
    ),
    squatSessionId: sessionId,
    sequence: sequence,
    acceptedReps: 1,
    detectorType: ContributionDetectorType.mlkit,
    detectorVersion: 'integration-v1',
    clientObservedAt: DateTime.now().toUtc(),
  );
}
