import 'package:cloud_firestore/cloud_firestore.dart';

import '../../debt/domain/debt.dart';
import '../../debt/infrastructure/firestore_debt_repository.dart';
import '../../task/domain/task_session.dart';
import '../../task/infrastructure/firestore_task_repository.dart';
import '../domain/recovery.dart';

final class FirestoreRecoveryRemoteStore implements RecoveryRemoteStore {
  FirestoreRecoveryRemoteStore(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<RecoveryUserPointer?> fetchUserPointer(String userId) async {
    if (userId.isEmpty) {
      throw const RecoveryFailure(RecoveryFailureKind.malformedData);
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data()!;
      final activeTaskSessionId = data['activeTaskSessionId'];
      if (activeTaskSessionId != null &&
          (activeTaskSessionId is! String || activeTaskSessionId.isEmpty)) {
        throw const RecoveryFailure(RecoveryFailureKind.malformedData);
      }
      return RecoveryUserPointer(
        activeTaskSessionId: activeTaskSessionId as String?,
      );
    } on Object catch (error) {
      throw _mapRecoveryFailure(error);
    }
  }

  @override
  Future<TaskSession?> fetchTask(String taskId) async {
    if (taskId.isEmpty) {
      throw const RecoveryFailure(RecoveryFailureKind.malformedData);
    }
    try {
      final snapshot = await _firestore
          .collection('taskSessions')
          .doc(taskId)
          .get(const GetOptions(source: Source.server));
      return snapshot.exists
          ? taskSessionFromFirestore(snapshot.id, snapshot.data()!)
          : null;
    } on Object catch (error) {
      throw _mapRecoveryFailure(error);
    }
  }

  @override
  Future<Debt?> fetchDebt(String debtId) async {
    if (debtId.isEmpty) {
      throw const RecoveryFailure(RecoveryFailureKind.malformedData);
    }
    try {
      final snapshot = await _firestore
          .collection('debts')
          .doc(debtId)
          .get(const GetOptions(source: Source.server));
      return snapshot.exists
          ? debtFromFirestore(snapshot.id, snapshot.data()!)
          : null;
    } on Object catch (error) {
      throw _mapRecoveryFailure(error);
    }
  }

  @override
  Future<List<Debt>> fetchFailedUserActiveDebts(String userId) async {
    if (userId.isEmpty) {
      throw const RecoveryFailure(RecoveryFailureKind.malformedData);
    }
    try {
      final snapshot = await _firestore
          .collection('debts')
          .where('failedUserId', isEqualTo: userId)
          .where('status', isEqualTo: DebtStatus.active.wireValue)
          .orderBy('lockExpiresAt')
          .limit(20)
          .get(const GetOptions(source: Source.server));
      return snapshot.docs
          .map((document) => debtFromFirestore(document.id, document.data()))
          .toList(growable: false);
    } on Object catch (error) {
      throw _mapRecoveryFailure(error);
    }
  }
}

RecoveryFailure _mapRecoveryFailure(Object error) {
  if (error is RecoveryFailure) {
    return error;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' ||
      'deadline-exceeded' => const RecoveryFailure(RecoveryFailureKind.offline),
      'permission-denied' || 'unauthenticated' => const RecoveryFailure(
        RecoveryFailureKind.unauthorized,
      ),
      _ => const RecoveryFailure(RecoveryFailureKind.unknown),
    };
  }
  return const RecoveryFailure(RecoveryFailureKind.malformedData);
}
