enum ContributionDetectorType {
  mlkit('mlkit');

  const ContributionDetectorType(this.wireValue);

  final String wireValue;

  static ContributionDetectorType? fromWireValue(String value) {
    for (final type in values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}

final class ContributionRequest {
  const ContributionRequest({
    required this.debtId,
    required this.userId,
    required this.eventId,
    required this.squatSessionId,
    required this.sequence,
    required this.acceptedReps,
    required this.detectorType,
    required this.detectorVersion,
    required this.clientObservedAt,
  });

  static const int acceptedRepsPerEvent = 1;
  static const int maximumSequence = 999999999;
  static final RegExp _documentId = RegExp(r'^[^/]{1,150}$');
  static final RegExp _sessionId = RegExp(r'^[A-Za-z0-9-]{16,64}$');
  static final RegExp _detectorVersion = RegExp(r'^[A-Za-z0-9._-]{1,40}$');

  final String debtId;
  final String userId;
  final String eventId;
  final String squatSessionId;
  final int sequence;
  final int acceptedReps;
  final ContributionDetectorType detectorType;
  final String detectorVersion;
  final DateTime clientObservedAt;

  bool get isValid {
    return _documentId.hasMatch(debtId) &&
        _documentId.hasMatch(userId) &&
        eventId ==
            ContributionEventId.build(
              userId: userId,
              squatSessionId: squatSessionId,
              sequence: sequence,
            ) &&
        eventId.length <= 240 &&
        _sessionId.hasMatch(squatSessionId) &&
        sequence >= 1 &&
        sequence <= maximumSequence &&
        acceptedReps == acceptedRepsPerEvent &&
        _detectorVersion.hasMatch(detectorVersion);
  }
}

final class ContributionEventId {
  const ContributionEventId._();

  static String build({
    required String userId,
    required String squatSessionId,
    required int sequence,
  }) => '${userId}_${squatSessionId}_$sequence';
}

final class ContributionEvent {
  const ContributionEvent({
    required this.id,
    required this.userId,
    required this.squatSessionId,
    required this.sequence,
    required this.acceptedReps,
    required this.detectorType,
    required this.detectorVersion,
    required this.clientObservedAt,
    required this.createdAt,
  });

  static const int schemaVersion = 1;

  final String id;
  final String userId;
  final String squatSessionId;
  final int sequence;
  final int acceptedReps;
  final ContributionDetectorType detectorType;
  final String detectorVersion;
  final DateTime clientObservedAt;
  final DateTime createdAt;
}

enum ContributionCommitDisposition { accepted, duplicate }

final class ContributionCommitResult {
  const ContributionCommitResult({
    required this.eventId,
    required this.disposition,
    required this.acceptedReps,
    required this.debtCompletedReps,
    required this.debtTotalReps,
    required this.debtCompleted,
  });

  final String eventId;
  final ContributionCommitDisposition disposition;
  final int acceptedReps;
  final int debtCompletedReps;
  final int debtTotalReps;
  final bool debtCompleted;

  bool get isDuplicate =>
      disposition == ContributionCommitDisposition.duplicate;
}

enum ContributionSyncStatus { detected, pending, confirmed, rejected }

enum ContributionRejectionReason {
  invalidRequest,
  debtNotFound,
  debtTerminal,
  debtFull,
  deadlineReached,
  unauthorized,
  conflict,
  outboxFull,
  malformedData,
  unknown,
}

final class ContributionFailure implements Exception {
  const ContributionFailure(this.reason);

  final ContributionRejectionReason reason;

  @override
  String toString() => 'ContributionFailure($reason)';
}
