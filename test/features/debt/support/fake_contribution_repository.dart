import 'dart:async';

import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/domain/contribution_repository.dart';

final class FakeContributionRepository implements ContributionRepository {
  final List<ContributionRequest> requests = [];
  final Map<String, ContributionCommitResult> committed = {};
  ContributionFailure? failure;
  Completer<void>? blocker;

  @override
  Future<ContributionCommitResult> submit(ContributionRequest request) async {
    requests.add(request);
    await blocker?.future;
    if (failure case final value?) {
      throw value;
    }
    final existing = committed[request.eventId];
    if (existing != null) {
      return ContributionCommitResult(
        eventId: request.eventId,
        disposition: ContributionCommitDisposition.duplicate,
        acceptedReps: 0,
        debtCompletedReps: existing.debtCompletedReps,
        debtTotalReps: existing.debtTotalReps,
        debtCompleted: existing.debtCompleted,
      );
    }
    final result = ContributionCommitResult(
      eventId: request.eventId,
      disposition: ContributionCommitDisposition.accepted,
      acceptedReps: 1,
      debtCompletedReps: committed.length + 1,
      debtTotalReps: 10,
      debtCompleted: false,
    );
    committed[request.eventId] = result;
    return result;
  }
}

final class InMemoryContributionOutbox implements ContributionOutbox {
  final Map<String, ContributionRequest> entries = {};

  @override
  Future<List<ContributionRequest>> loadForUser(String userId) async {
    return entries.values
        .where((request) => request.userId == userId)
        .toList(growable: false)
      ..sort(
        (left, right) =>
            left.clientObservedAt.compareTo(right.clientObservedAt),
      );
  }

  @override
  Future<void> put(ContributionRequest request) async {
    final existing = entries[request.eventId];
    if (existing != null && !_same(existing, request)) {
      throw const ContributionFailure(ContributionRejectionReason.conflict);
    }
    entries[request.eventId] = request;
  }

  @override
  Future<void> remove(String eventId) async {
    entries.remove(eventId);
  }
}

ContributionRequest contributionRequest({
  int sequence = 1,
  String userId = 'alice',
  String debtId = 'debt-1',
}) {
  const sessionId = 'session-12345678';
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
    detectorVersion: 'phase9-detector-v1',
    clientObservedAt: DateTime.utc(2026, 7, 30, 10, 0, sequence),
  );
}

bool _same(ContributionRequest left, ContributionRequest right) {
  return left.debtId == right.debtId &&
      left.userId == right.userId &&
      left.eventId == right.eventId &&
      left.squatSessionId == right.squatSessionId &&
      left.sequence == right.sequence &&
      left.acceptedReps == right.acceptedReps &&
      left.detectorType == right.detectorType &&
      left.detectorVersion == right.detectorVersion &&
      left.clientObservedAt == right.clientObservedAt;
}
