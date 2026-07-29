import '../domain/contribution.dart';
import '../domain/contribution_repository.dart';

final class ContributionDelivery {
  const ContributionDelivery({
    required this.request,
    required this.status,
    this.commitResult,
    this.failure,
  });

  final ContributionRequest request;
  final ContributionSyncStatus status;
  final ContributionCommitResult? commitResult;
  final ContributionFailure? failure;
}

final class SubmitContribution {
  const SubmitContribution(this._repository, this._outbox);

  final ContributionRepository _repository;
  final ContributionOutbox _outbox;

  Future<ContributionDelivery> recordAcceptedRep(
    ContributionRequest request,
  ) async {
    if (!request.isValid) {
      return ContributionDelivery(
        request: request,
        status: ContributionSyncStatus.rejected,
        failure: const ContributionFailure(
          ContributionRejectionReason.invalidRequest,
        ),
      );
    }
    try {
      await _outbox.put(request);
    } on ContributionFailure catch (failure) {
      return ContributionDelivery(
        request: request,
        status: ContributionSyncStatus.rejected,
        failure: failure,
      );
    }
    return _deliver(request);
  }

  Future<List<ContributionDelivery>> flushPending(String userId) async {
    final pending = await _outbox.loadForUser(userId);
    final deliveries = <ContributionDelivery>[];
    for (final request in pending) {
      final delivery = await _deliver(request);
      deliveries.add(delivery);
      if (delivery.status == ContributionSyncStatus.pending) {
        break;
      }
    }
    return deliveries;
  }

  Future<int> pendingCount(String userId) async {
    return (await _outbox.loadForUser(userId)).length;
  }

  Future<ContributionDelivery> _deliver(ContributionRequest request) async {
    try {
      final result = await _repository.submit(request);
      await _outbox.remove(request.eventId);
      return ContributionDelivery(
        request: request,
        status: ContributionSyncStatus.confirmed,
        commitResult: result,
      );
    } on ContributionFailure catch (failure) {
      if (_isFinalRejection(failure.reason)) {
        await _outbox.remove(request.eventId);
        return ContributionDelivery(
          request: request,
          status: ContributionSyncStatus.rejected,
          failure: failure,
        );
      }
      return ContributionDelivery(
        request: request,
        status: ContributionSyncStatus.pending,
        failure: failure,
      );
    } on Object {
      return ContributionDelivery(
        request: request,
        status: ContributionSyncStatus.pending,
        failure: const ContributionFailure(ContributionRejectionReason.unknown),
      );
    }
  }
}

bool _isFinalRejection(ContributionRejectionReason reason) {
  return switch (reason) {
    ContributionRejectionReason.invalidRequest ||
    ContributionRejectionReason.debtNotFound ||
    ContributionRejectionReason.debtTerminal ||
    ContributionRejectionReason.debtFull ||
    ContributionRejectionReason.deadlineReached ||
    ContributionRejectionReason.unauthorized ||
    ContributionRejectionReason.conflict ||
    ContributionRejectionReason.outboxFull ||
    ContributionRejectionReason.malformedData => true,
    ContributionRejectionReason.offline ||
    ContributionRejectionReason.unknown => false,
  };
}
