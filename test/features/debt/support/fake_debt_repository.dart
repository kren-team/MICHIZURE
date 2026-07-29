import 'dart:async';

import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/domain/debt_repository.dart';

final class FakeDebtRepository implements DebtRepository {
  final activeController =
      StreamController<DebtSnapshot<List<Debt>>>.broadcast();
  final failedUserController =
      StreamController<DebtSnapshot<List<Debt>>>.broadcast();
  final Map<String, StreamController<DebtSnapshot<Debt?>>> debtControllers = {};
  final Map<
    String,
    StreamController<DebtSnapshot<List<DebtContributionSummary>>>
  >
  contributionControllers = {};
  final List<String> expiredDebtIds = [];
  final List<String> watchedGroupIds = [];
  Debt? expireResult;
  Object? expireError;

  @override
  Stream<DebtSnapshot<List<Debt>>> watchActiveDebts(String groupId) {
    watchedGroupIds.add(groupId);
    return activeController.stream;
  }

  @override
  Stream<DebtSnapshot<List<Debt>>> watchFailedUserActiveDebts(String userId) {
    return failedUserController.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          sink.add(data);
        },
      ),
    );
  }

  @override
  Stream<DebtSnapshot<Debt?>> watchDebt(String debtId) {
    return debtControllers
        .putIfAbsent(
          debtId,
          () => StreamController<DebtSnapshot<Debt?>>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<DebtSnapshot<List<DebtContributionSummary>>> watchContributions(
    String debtId,
  ) {
    return contributionControllers
        .putIfAbsent(
          debtId,
          () =>
              StreamController<
                DebtSnapshot<List<DebtContributionSummary>>
              >.broadcast(),
        )
        .stream;
  }

  @override
  Future<Debt> expireDebt(String debtId) async {
    expiredDebtIds.add(debtId);
    if (expireError case final error?) {
      throw error;
    }
    return expireResult!;
  }

  Future<void> dispose() async {
    await activeController.close();
    await failedUserController.close();
    for (final controller in debtControllers.values) {
      await controller.close();
    }
    for (final controller in contributionControllers.values) {
      await controller.close();
    }
  }
}
