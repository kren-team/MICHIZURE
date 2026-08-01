import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/debt.dart';
import '../domain/debt_failure.dart';
import '../domain/debt_repository.dart';

final class FirestoreDebtRepository implements DebtRepository {
  FirestoreDebtRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _debts =>
      _firestore.collection('debts');

  @override
  Stream<DebtSnapshot<Debt?>> watchDebt(String debtId) {
    return _debts
        .doc(debtId)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          return DebtSnapshot(
            value: snapshot.exists
                ? debtFromFirestore(snapshot.id, snapshot.data()!)
                : null,
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          );
        })
        .handleError(_throwMappedFailure);
  }

  @override
  Stream<DebtSnapshot<List<Debt>>> watchActiveDebts(String groupId) {
    if (groupId.isEmpty) {
      return Stream.error(const DebtFailure(DebtFailureKind.invalidData));
    }
    return _debts
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: DebtStatus.active.wireValue)
        .orderBy('lockExpiresAt')
        .limit(20)
        .snapshots(includeMetadataChanges: true)
        .map(_mapDebtQuery)
        .handleError(_throwMappedFailure);
  }

  @override
  Stream<DebtSnapshot<List<Debt>>> watchFailedUserActiveDebts(String userId) {
    if (userId.isEmpty) {
      return Stream.error(const DebtFailure(DebtFailureKind.invalidData));
    }
    return _debts
        .where('failedUserId', isEqualTo: userId)
        .where('status', isEqualTo: DebtStatus.active.wireValue)
        .orderBy('lockExpiresAt')
        .limit(20)
        .snapshots(includeMetadataChanges: true)
        .map(_mapDebtQuery)
        .handleError(_throwMappedFailure);
  }

  @override
  Stream<DebtSnapshot<List<DebtContributionSummary>>> watchContributions(
    String debtId,
  ) {
    if (debtId.isEmpty) {
      return Stream.error(const DebtFailure(DebtFailureKind.invalidData));
    }
    return _debts
        .doc(debtId)
        .collection('contributions')
        .orderBy('lastContributedAt', descending: true)
        .limit(40)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => DebtSnapshot(
            value: snapshot.docs
                .map(
                  (document) => debtContributionSummaryFromFirestore(
                    document.id,
                    document.data(),
                  ),
                )
                .toList(growable: false),
            isFromCache: snapshot.metadata.isFromCache,
            hasPendingWrites: snapshot.metadata.hasPendingWrites,
          ),
        )
        .handleError(_throwMappedFailure);
  }

  @override
  Future<Debt> expireDebt(String debtId) async {
    if (debtId.isEmpty) {
      throw const DebtFailure(DebtFailureKind.invalidData);
    }
    final reference = _debts.doc(debtId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          throw const DebtFailure(DebtFailureKind.notFound);
        }
        final debt = debtFromFirestore(snapshot.id, snapshot.data()!);
        if (debt.status != DebtStatus.active) {
          return;
        }
        transaction.update(reference, {
          'status': DebtStatus.expired.wireValue,
          'closedAt': FieldValue.serverTimestamp(),
        });
      });
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      if (!snapshot.exists) {
        throw const DebtFailure(DebtFailureKind.notFound);
      }
      return debtFromFirestore(snapshot.id, snapshot.data()!);
    } on Object catch (error) {
      throw mapDebtFailure(error);
    }
  }
}

DebtSnapshot<List<Debt>> _mapDebtQuery(
  QuerySnapshot<Map<String, dynamic>> snapshot,
) {
  return DebtSnapshot(
    value: snapshot.docs
        .map((document) => debtFromFirestore(document.id, document.data()))
        .toList(growable: false),
    isFromCache: snapshot.metadata.isFromCache,
    hasPendingWrites: snapshot.metadata.hasPendingWrites,
  );
}

Debt debtFromFirestore(String debtId, Map<String, dynamic> data) {
  const expectedKeys = {
    'groupId',
    'failedUserId',
    'failedTaskSessionId',
    'memberCountAtFailure',
    'repsPerMember',
    'totalReps',
    'completedReps',
    'status',
    'createdAt',
    'lockExpiresAt',
    'closedAt',
    'lastContributionAt',
    'lastContributionEventId',
    'schemaVersion',
  };
  final groupId = data['groupId'];
  final failedUserId = data['failedUserId'];
  final statusValue = data['status'];
  final status = statusValue is String
      ? DebtStatus.fromWireValue(statusValue)
      : null;
  final memberCount = data['memberCountAtFailure'];
  final repsPerMember = data['repsPerMember'];
  final totalReps = data['totalReps'];
  final completedReps = data['completedReps'];
  final createdAt = data['createdAt'];
  final lockExpiresAt = data['lockExpiresAt'];
  final closedAt = data['closedAt'];
  final lastContributionAt = data['lastContributionAt'];
  final lastContributionEventId = data['lastContributionEventId'];
  if (data.keys.toSet().length != expectedKeys.length ||
      !data.keys.toSet().containsAll(expectedKeys) ||
      groupId is! String ||
      groupId.isEmpty ||
      failedUserId is! String ||
      failedUserId.isEmpty ||
      data['failedTaskSessionId'] != debtId ||
      memberCount is! int ||
      memberCount < 1 ||
      memberCount > 40 ||
      repsPerMember != Debt.repsPerMemberMvp ||
      totalReps != memberCount * Debt.repsPerMemberMvp ||
      completedReps is! int ||
      completedReps < 0 ||
      completedReps > totalReps ||
      status == null ||
      createdAt is! Timestamp ||
      lockExpiresAt is! Timestamp ||
      lockExpiresAt.toDate().isBefore(createdAt.toDate()) ||
      (closedAt != null && closedAt is! Timestamp) ||
      (lastContributionAt != null && lastContributionAt is! Timestamp) ||
      (lastContributionEventId != null &&
          (lastContributionEventId is! String ||
              lastContributionEventId.isEmpty)) ||
      data['schemaVersion'] != Debt.schemaVersion ||
      !_validDebtTerminalShape(
        status: status,
        completedReps: completedReps,
        totalReps: totalReps as int,
        closedAt: closedAt,
      )) {
    throw const DebtFailure(DebtFailureKind.invalidData);
  }
  return Debt(
    id: debtId,
    groupId: groupId,
    failedUserId: failedUserId,
    failedTaskSessionId: debtId,
    memberCountAtFailure: memberCount,
    repsPerMember: repsPerMember as int,
    totalReps: totalReps,
    completedReps: completedReps,
    status: status,
    createdAt: createdAt.toDate().toUtc(),
    lockExpiresAt: lockExpiresAt.toDate().toUtc(),
    closedAt: (closedAt as Timestamp?)?.toDate().toUtc(),
    lastContributionAt: (lastContributionAt as Timestamp?)?.toDate().toUtc(),
    lastContributionEventId: lastContributionEventId as String?,
  );
}

DebtContributionSummary debtContributionSummaryFromFirestore(
  String userId,
  Map<String, dynamic> data,
) {
  const expectedKeys = {
    'userId',
    'totalReps',
    'lastEventId',
    'lastContributedAt',
    'schemaVersion',
  };
  final totalReps = data['totalReps'];
  final lastEventId = data['lastEventId'];
  final lastContributedAt = data['lastContributedAt'];
  if (data.keys.toSet().length != expectedKeys.length ||
      !data.keys.toSet().containsAll(expectedKeys) ||
      data['userId'] != userId ||
      totalReps is! int ||
      totalReps < 0 ||
      lastEventId is! String ||
      lastEventId.isEmpty ||
      lastContributedAt is! Timestamp ||
      data['schemaVersion'] != DebtContributionSummary.schemaVersion) {
    throw const DebtFailure(DebtFailureKind.invalidData);
  }
  return DebtContributionSummary(
    userId: userId,
    totalReps: totalReps,
    lastEventId: lastEventId,
    lastContributedAt: lastContributedAt.toDate().toUtc(),
  );
}

bool _validDebtTerminalShape({
  required DebtStatus status,
  required int completedReps,
  required int totalReps,
  required Object? closedAt,
}) {
  return switch (status) {
    DebtStatus.active => closedAt == null && completedReps < totalReps,
    DebtStatus.completed => closedAt is Timestamp && completedReps == totalReps,
    DebtStatus.expired => closedAt is Timestamp && completedReps < totalReps,
  };
}

DebtFailure mapDebtFailure(Object error) {
  if (error is DebtFailure) {
    return error;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => const DebtFailure(DebtFailureKind.rulesDenied),
      'unavailable' ||
      'deadline-exceeded' => const DebtFailure(DebtFailureKind.offline),
      'aborted' => const DebtFailure(DebtFailureKind.conflict),
      _ => const DebtFailure(DebtFailureKind.unknown),
    };
  }
  return const DebtFailure(DebtFailureKind.unknown);
}

Never _throwMappedFailure(Object error, StackTrace stackTrace) {
  Error.throwWithStackTrace(mapDebtFailure(error), stackTrace);
}
