import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/time/clock.dart';
import '../domain/contribution.dart';
import '../domain/contribution_repository.dart';
import '../domain/debt.dart';
import 'firestore_debt_repository.dart';

final class FirestoreContributionRepository implements ContributionRepository {
  FirestoreContributionRepository(this._firestore, this._clock);

  final FirebaseFirestore _firestore;
  final Clock _clock;

  CollectionReference<Map<String, dynamic>> get _debts =>
      _firestore.collection('debts');

  @override
  Future<ContributionCommitResult> submit(ContributionRequest request) async {
    if (!request.isValid) {
      throw const ContributionFailure(
        ContributionRejectionReason.invalidRequest,
      );
    }
    final debtReference = _debts.doc(request.debtId);
    final eventReference = debtReference
        .collection('contributionEvents')
        .doc(request.eventId);
    final summaryReference = debtReference
        .collection('contributions')
        .doc(request.userId);

    try {
      return await _firestore.runTransaction((transaction) async {
        // Firestore transactions require every read before the first write.
        final debtSnapshot = await transaction.get(debtReference);
        final eventSnapshot = await transaction.get(eventReference);
        final summarySnapshot = await transaction.get(summaryReference);

        if (!debtSnapshot.exists) {
          throw const ContributionFailure(
            ContributionRejectionReason.debtNotFound,
          );
        }
        final debt = debtFromFirestore(debtSnapshot.id, debtSnapshot.data()!);

        if (eventSnapshot.exists) {
          final event = contributionEventFromFirestore(
            eventSnapshot.id,
            eventSnapshot.data()!,
          );
          if (!_matchesRequest(event, request)) {
            throw const ContributionFailure(
              ContributionRejectionReason.conflict,
            );
          }
          if (!summarySnapshot.exists) {
            throw const ContributionFailure(
              ContributionRejectionReason.malformedData,
            );
          }
          debtContributionSummaryFromFirestore(
            summarySnapshot.id,
            summarySnapshot.data()!,
          );
          return ContributionCommitResult(
            eventId: request.eventId,
            disposition: ContributionCommitDisposition.duplicate,
            acceptedReps: 0,
            debtCompletedReps: debt.completedReps,
            debtTotalReps: debt.totalReps,
            debtCompleted: debt.status == DebtStatus.completed,
          );
        }

        if (debt.status != DebtStatus.active) {
          throw const ContributionFailure(
            ContributionRejectionReason.debtTerminal,
          );
        }
        if (!_clock.now().toUtc().isBefore(debt.lockExpiresAt)) {
          throw const ContributionFailure(
            ContributionRejectionReason.deadlineReached,
          );
        }
        if (debt.completedReps >= debt.totalReps) {
          throw const ContributionFailure(ContributionRejectionReason.debtFull);
        }

        final previousSummary = summarySnapshot.exists
            ? debtContributionSummaryFromFirestore(
                summarySnapshot.id,
                summarySnapshot.data()!,
              )
            : null;
        final nextCompleted = debt.completedReps + 1;
        final completesDebt = nextCompleted == debt.totalReps;

        transaction.set(eventReference, {
          'userId': request.userId,
          'squatSessionId': request.squatSessionId,
          'sequence': request.sequence,
          'acceptedReps': request.acceptedReps,
          'detectorType': request.detectorType.wireValue,
          'detectorVersion': request.detectorVersion,
          'clientObservedAt': Timestamp.fromDate(
            request.clientObservedAt.toUtc(),
          ),
          'createdAt': FieldValue.serverTimestamp(),
          'schemaVersion': ContributionEvent.schemaVersion,
        });
        transaction.set(summaryReference, {
          'userId': request.userId,
          'totalReps': (previousSummary?.totalReps ?? 0) + 1,
          'lastEventId': request.eventId,
          'lastContributedAt': FieldValue.serverTimestamp(),
          'schemaVersion': DebtContributionSummary.schemaVersion,
        });
        transaction.update(debtReference, {
          'completedReps': nextCompleted,
          'status': completesDebt
              ? DebtStatus.completed.wireValue
              : DebtStatus.active.wireValue,
          'closedAt': completesDebt ? FieldValue.serverTimestamp() : null,
          'lastContributionAt': FieldValue.serverTimestamp(),
          'lastContributionEventId': request.eventId,
        });

        return ContributionCommitResult(
          eventId: request.eventId,
          disposition: ContributionCommitDisposition.accepted,
          acceptedReps: 1,
          debtCompletedReps: nextCompleted,
          debtTotalReps: debt.totalReps,
          debtCompleted: completesDebt,
        );
      });
    } on Object catch (error) {
      throw mapContributionFailure(error);
    }
  }
}

ContributionEvent contributionEventFromFirestore(
  String eventId,
  Map<String, dynamic> data,
) {
  const expectedKeys = {
    'userId',
    'squatSessionId',
    'sequence',
    'acceptedReps',
    'detectorType',
    'detectorVersion',
    'clientObservedAt',
    'createdAt',
    'schemaVersion',
  };
  final userId = data['userId'];
  final squatSessionId = data['squatSessionId'];
  final sequence = data['sequence'];
  final acceptedReps = data['acceptedReps'];
  final detectorTypeValue = data['detectorType'];
  final detectorType = detectorTypeValue is String
      ? ContributionDetectorType.fromWireValue(detectorTypeValue)
      : null;
  final detectorVersion = data['detectorVersion'];
  final clientObservedAt = data['clientObservedAt'];
  final createdAt = data['createdAt'];
  if (data.keys.toSet().length != expectedKeys.length ||
      !data.keys.toSet().containsAll(expectedKeys) ||
      userId is! String ||
      squatSessionId is! String ||
      sequence is! int ||
      acceptedReps != ContributionRequest.acceptedRepsPerEvent ||
      detectorType == null ||
      detectorVersion is! String ||
      clientObservedAt is! Timestamp ||
      createdAt is! Timestamp ||
      data['schemaVersion'] != ContributionEvent.schemaVersion) {
    throw const ContributionFailure(ContributionRejectionReason.malformedData);
  }
  final requestShape = ContributionRequest(
    debtId: 'converter-validation',
    userId: userId,
    eventId: eventId,
    squatSessionId: squatSessionId,
    sequence: sequence,
    acceptedReps: acceptedReps as int,
    detectorType: detectorType,
    detectorVersion: detectorVersion,
    clientObservedAt: clientObservedAt.toDate().toUtc(),
  );
  if (!requestShape.isValid) {
    throw const ContributionFailure(ContributionRejectionReason.malformedData);
  }
  return ContributionEvent(
    id: eventId,
    userId: userId,
    squatSessionId: squatSessionId,
    sequence: sequence,
    acceptedReps: acceptedReps,
    detectorType: detectorType,
    detectorVersion: detectorVersion,
    clientObservedAt: clientObservedAt.toDate().toUtc(),
    createdAt: createdAt.toDate().toUtc(),
  );
}

ContributionFailure mapContributionFailure(Object error) {
  if (error is ContributionFailure) {
    return error;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => const ContributionFailure(
        ContributionRejectionReason.unauthorized,
      ),
      'unavailable' || 'deadline-exceeded' => const ContributionFailure(
        ContributionRejectionReason.offline,
      ),
      'aborted' => const ContributionFailure(
        ContributionRejectionReason.conflict,
      ),
      _ => const ContributionFailure(ContributionRejectionReason.unknown),
    };
  }
  return const ContributionFailure(ContributionRejectionReason.unknown);
}

bool _matchesRequest(ContributionEvent event, ContributionRequest request) {
  return event.id == request.eventId &&
      event.userId == request.userId &&
      event.squatSessionId == request.squatSessionId &&
      event.sequence == request.sequence &&
      event.acceptedReps == request.acceptedReps &&
      event.detectorType == request.detectorType &&
      event.detectorVersion == request.detectorVersion &&
      event.clientObservedAt.millisecondsSinceEpoch ==
          request.clientObservedAt.toUtc().millisecondsSinceEpoch;
}
