import 'contribution.dart';

abstract interface class ContributionRepository {
  Future<ContributionCommitResult> submit(ContributionRequest request);
}

abstract interface class ContributionOutbox {
  Future<List<ContributionRequest>> loadForUser(String userId);

  Future<void> put(ContributionRequest request);

  Future<void> remove(String eventId);
}
