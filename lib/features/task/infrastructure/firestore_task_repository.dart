import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/time/clock.dart';
import '../../debt/domain/debt.dart';
import '../../debt/infrastructure/firestore_debt_repository.dart';
import '../domain/task_failure.dart';
import '../domain/task_repository.dart';
import '../domain/task_session.dart';

final class FirestoreTaskRepository implements TaskRepository {
  FirestoreTaskRepository(this._firestore, [this._clock = const SystemClock()]);

  final FirebaseFirestore _firestore;
  final Clock _clock;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _firestore.collection('taskSessions');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection('groups');
  CollectionReference<Map<String, dynamic>> get _debts =>
      _firestore.collection('debts');

  @override
  Stream<TaskSession?> watchTask(String taskId) {
    return _tasks.doc(taskId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return taskSessionFromFirestore(snapshot.id, snapshot.data()!);
    });
  }

  @override
  Future<TaskSession> startTask(StartTaskRequest request) async {
    final content = TaskContentValidator.normalize(request.content);
    if (!TaskContentValidator.isValid(content)) {
      throw const TaskFailure(TaskFailureKind.invalidContent);
    }
    if (!TaskDurationValidator.isValidSeconds(request.durationSeconds)) {
      throw const TaskFailure(TaskFailureKind.invalidDuration);
    }
    if (request.ownerUid.isEmpty || request.groupId.isEmpty) {
      throw const TaskFailure(TaskFailureKind.invalidData);
    }

    final taskReference = _tasks.doc();
    final userReference = _users.doc(request.ownerUid);
    final memberReference = _groups
        .doc(request.groupId)
        .collection('members')
        .doc(request.ownerUid);

    try {
      await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userReference);
        final memberSnapshot = await transaction.get(memberReference);
        if (!userSnapshot.exists || !memberSnapshot.exists) {
          throw const TaskFailure(TaskFailureKind.groupRequired);
        }
        final userData = userSnapshot.data()!;
        if (userData['groupId'] != request.groupId) {
          throw const TaskFailure(TaskFailureKind.groupRequired);
        }
        if (userData['activeTaskSessionId'] != null) {
          throw const TaskFailure(TaskFailureKind.alreadyActive);
        }

        final startedAt = _clock.now().toUtc();
        final expectedEndAt = startedAt.add(
          Duration(seconds: request.durationSeconds),
        );
        transaction.set(taskReference, {
          'ownerUid': request.ownerUid,
          'groupId': request.groupId,
          'content': content,
          'durationSec': request.durationSeconds,
          'startedAt': Timestamp.fromDate(startedAt),
          'serverRecordedAt': FieldValue.serverTimestamp(),
          'expectedEndAt': Timestamp.fromDate(expectedEndAt),
          'status': TaskSessionStatus.running.wireValue,
          'endedAt': null,
          'failureReason': null,
          'failureEventId': null,
          'groupMemberCountAtFailure': null,
          'debtId': null,
          'lockDurationSec': TaskSession.lockDurationSecondsMvp,
          'guardConfigVersion': TaskSession.guardConfigVersionMvp,
          'schemaVersion': TaskSession.schemaVersion,
        });
        transaction.update(userReference, {
          'activeTaskSessionId': taskReference.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return _readTaskFromServer(taskReference);
    } on Object catch (error) {
      throw mapTaskFailure(error);
    }
  }

  @override
  Future<TaskSession> succeedTask({
    required String ownerUid,
    required String taskId,
  }) async {
    final taskReference = _tasks.doc(taskId);
    final userReference = _users.doc(ownerUid);
    try {
      await _firestore.runTransaction((transaction) async {
        final taskSnapshot = await transaction.get(taskReference);
        final userSnapshot = await transaction.get(userReference);
        if (!taskSnapshot.exists || !userSnapshot.exists) {
          throw const TaskFailure(TaskFailureKind.noActiveTask);
        }
        final task = taskSessionFromFirestore(
          taskSnapshot.id,
          taskSnapshot.data()!,
        );
        if (task.ownerUid != ownerUid) {
          throw const TaskFailure(TaskFailureKind.rulesDenied);
        }
        if (task.status == TaskSessionStatus.succeeded &&
            userSnapshot.data()!['activeTaskSessionId'] == null) {
          return;
        }
        if (task.status != TaskSessionStatus.running ||
            userSnapshot.data()!['activeTaskSessionId'] != taskId) {
          throw const TaskFailure(TaskFailureKind.notRunning);
        }
        if (!task.deadlineReachedAt(_clock.now().toUtc())) {
          throw const TaskFailure(TaskFailureKind.deadlineNotReached);
        }

        transaction.update(taskReference, {
          'status': TaskSessionStatus.succeeded.wireValue,
          'endedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(userReference, {
          'activeTaskSessionId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return _readTaskFromServer(taskReference);
    } on Object catch (error) {
      throw mapTaskFailure(error);
    }
  }

  @override
  Future<FailedTaskResult> failTaskAndCreateDebt({
    required String ownerUid,
    required String taskId,
    required TaskFailureReason reason,
    required String failureEventId,
  }) async {
    if (failureEventId.isEmpty || failureEventId.length > 200) {
      throw const TaskFailure(TaskFailureKind.invalidData);
    }
    final taskReference = _tasks.doc(taskId);
    final userReference = _users.doc(ownerUid);
    final debtReference = _debts.doc(taskId);

    try {
      await _firestore.runTransaction((transaction) async {
        final taskSnapshot = await transaction.get(taskReference);
        final userSnapshot = await transaction.get(userReference);
        final debtSnapshot = await transaction.get(debtReference);
        if (!taskSnapshot.exists || !userSnapshot.exists) {
          throw const TaskFailure(TaskFailureKind.noActiveTask);
        }
        final task = taskSessionFromFirestore(
          taskSnapshot.id,
          taskSnapshot.data()!,
        );
        if (task.ownerUid != ownerUid) {
          throw const TaskFailure(TaskFailureKind.rulesDenied);
        }
        if (task.status == TaskSessionStatus.failed &&
            task.failureEventId == failureEventId &&
            debtSnapshot.exists) {
          return;
        }
        if (task.status != TaskSessionStatus.running ||
            userSnapshot.data()!['activeTaskSessionId'] != taskId ||
            debtSnapshot.exists) {
          throw const TaskFailure(TaskFailureKind.notRunning);
        }

        final groupReference = _groups.doc(task.groupId);
        final groupSnapshot = await transaction.get(groupReference);
        if (!groupSnapshot.exists ||
            userSnapshot.data()!['groupId'] != task.groupId) {
          throw const TaskFailure(TaskFailureKind.groupRequired);
        }
        final memberCount = groupSnapshot.data()!['memberCount'];
        if (memberCount is! int || memberCount < 1 || memberCount > 40) {
          throw const TaskFailure(TaskFailureKind.invalidData);
        }

        final endedAt = _clock.now().toUtc();
        final lockExpiresAt = endedAt.add(
          Duration(seconds: task.lockDurationSeconds),
        );
        transaction.update(taskReference, {
          'status': TaskSessionStatus.failed.wireValue,
          'endedAt': Timestamp.fromDate(endedAt),
          'failureReason': reason.wireValue,
          'failureEventId': failureEventId,
          'groupMemberCountAtFailure': memberCount,
          'debtId': taskId,
        });
        transaction.update(userReference, {
          'activeTaskSessionId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(debtReference, {
          'groupId': task.groupId,
          'failedUserId': ownerUid,
          'failedTaskSessionId': taskId,
          'memberCountAtFailure': memberCount,
          'repsPerMember': Debt.repsPerMemberMvp,
          'totalReps': memberCount * Debt.repsPerMemberMvp,
          'completedReps': 0,
          'status': DebtStatus.active.wireValue,
          'createdAt': FieldValue.serverTimestamp(),
          'lockExpiresAt': Timestamp.fromDate(lockExpiresAt),
          'closedAt': null,
          'lastContributionAt': null,
          'lastContributionEventId': null,
          'schemaVersion': Debt.schemaVersion,
        });
      });

      final task = await _readTaskFromServer(taskReference);
      final debtSnapshot = await debtReference.get(
        const GetOptions(source: Source.server),
      );
      if (!debtSnapshot.exists) {
        throw const TaskFailure(TaskFailureKind.invalidData);
      }
      return FailedTaskResult(
        task: task,
        debt: debtFromFirestore(debtSnapshot.id, debtSnapshot.data()!),
      );
    } on Object catch (error) {
      throw mapTaskFailure(error);
    }
  }

  Future<TaskSession> _readTaskFromServer(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    final snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );
    if (!snapshot.exists) {
      throw const TaskFailure(TaskFailureKind.invalidData);
    }
    return taskSessionFromFirestore(snapshot.id, snapshot.data()!);
  }
}

TaskSession taskSessionFromFirestore(String taskId, Map<String, dynamic> data) {
  const expectedKeys = {
    'ownerUid',
    'groupId',
    'content',
    'durationSec',
    'startedAt',
    'serverRecordedAt',
    'expectedEndAt',
    'status',
    'endedAt',
    'failureReason',
    'failureEventId',
    'groupMemberCountAtFailure',
    'debtId',
    'lockDurationSec',
    'guardConfigVersion',
    'schemaVersion',
  };
  if (!_sameKeys(data.keys.toSet(), expectedKeys)) {
    throw const TaskFailure(TaskFailureKind.invalidData);
  }

  final ownerUid = data['ownerUid'];
  final groupId = data['groupId'];
  final content = data['content'];
  final durationSeconds = data['durationSec'];
  final startedAt = data['startedAt'];
  final serverRecordedAt = data['serverRecordedAt'];
  final expectedEndAt = data['expectedEndAt'];
  final statusValue = data['status'];
  final endedAt = data['endedAt'];
  final failureReasonValue = data['failureReason'];
  final failureEventId = data['failureEventId'];
  final memberCount = data['groupMemberCountAtFailure'];
  final debtId = data['debtId'];
  final lockDurationSeconds = data['lockDurationSec'];
  final guardConfigVersion = data['guardConfigVersion'];
  final status = statusValue is String
      ? TaskSessionStatus.fromWireValue(statusValue)
      : null;
  final failureReason = failureReasonValue is String
      ? TaskFailureReason.fromWireValue(failureReasonValue)
      : null;

  if (ownerUid is! String ||
      ownerUid.isEmpty ||
      groupId is! String ||
      groupId.isEmpty ||
      content is! String ||
      !TaskContentValidator.isValid(content) ||
      TaskContentValidator.normalize(content) != content ||
      durationSeconds is! int ||
      !TaskDurationValidator.isValidSeconds(durationSeconds) ||
      startedAt is! Timestamp ||
      serverRecordedAt is! Timestamp ||
      expectedEndAt is! Timestamp ||
      expectedEndAt.toDate() !=
          startedAt.toDate().add(Duration(seconds: durationSeconds)) ||
      status == null ||
      (endedAt != null && endedAt is! Timestamp) ||
      (failureReasonValue != null && failureReason == null) ||
      (failureEventId != null && failureEventId is! String) ||
      (memberCount != null && memberCount is! int) ||
      (debtId != null && debtId is! String) ||
      lockDurationSeconds != TaskSession.lockDurationSecondsMvp ||
      guardConfigVersion != TaskSession.guardConfigVersionMvp ||
      data['schemaVersion'] != TaskSession.schemaVersion ||
      !_validTerminalShape(
        status: status,
        endedAt: endedAt,
        failureReason: failureReason,
        failureEventId: failureEventId,
        memberCount: memberCount,
        debtId: debtId,
        taskId: taskId,
      )) {
    throw const TaskFailure(TaskFailureKind.invalidData);
  }

  return TaskSession(
    id: taskId,
    ownerUid: ownerUid,
    groupId: groupId,
    content: content,
    durationSeconds: durationSeconds,
    startedAt: startedAt.toDate().toUtc(),
    serverRecordedAt: serverRecordedAt.toDate().toUtc(),
    expectedEndAt: expectedEndAt.toDate().toUtc(),
    status: status,
    endedAt: (endedAt as Timestamp?)?.toDate().toUtc(),
    failureReason: failureReason,
    failureEventId: failureEventId as String?,
    groupMemberCountAtFailure: memberCount as int?,
    debtId: debtId as String?,
    lockDurationSeconds: lockDurationSeconds as int,
    guardConfigVersion: guardConfigVersion as int,
  );
}

TaskFailure mapTaskFailure(Object error) {
  if (error is TaskFailure) {
    return error;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => const TaskFailure(TaskFailureKind.rulesDenied),
      'unavailable' ||
      'deadline-exceeded' => const TaskFailure(TaskFailureKind.offline),
      'aborted' ||
      'already-exists' => const TaskFailure(TaskFailureKind.conflict),
      _ => const TaskFailure(TaskFailureKind.unknown),
    };
  }
  return const TaskFailure(TaskFailureKind.unknown);
}

bool _validTerminalShape({
  required TaskSessionStatus status,
  required Object? endedAt,
  required TaskFailureReason? failureReason,
  required Object? failureEventId,
  required Object? memberCount,
  required Object? debtId,
  required String taskId,
}) {
  return switch (status) {
    TaskSessionStatus.running =>
      endedAt == null &&
          failureReason == null &&
          failureEventId == null &&
          memberCount == null &&
          debtId == null,
    TaskSessionStatus.succeeded =>
      endedAt is Timestamp &&
          failureReason == null &&
          failureEventId == null &&
          memberCount == null &&
          debtId == null,
    TaskSessionStatus.failed =>
      endedAt is Timestamp &&
          failureReason != null &&
          failureEventId is String &&
          failureEventId.isNotEmpty &&
          memberCount is int &&
          memberCount >= 1 &&
          memberCount <= 40 &&
          debtId == taskId,
  };
}

bool _sameKeys(Set<String> actual, Set<String> expected) =>
    actual.length == expected.length && actual.containsAll(expected);
