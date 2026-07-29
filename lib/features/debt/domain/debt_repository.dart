import 'debt.dart';

abstract interface class DebtRepository {
  Stream<DebtSnapshot<Debt?>> watchDebt(String debtId);

  Stream<DebtSnapshot<List<Debt>>> watchActiveDebts(String groupId);

  Stream<DebtSnapshot<List<Debt>>> watchFailedUserActiveDebts(String userId);

  Stream<DebtSnapshot<List<DebtContributionSummary>>> watchContributions(
    String debtId,
  );

  Future<Debt> expireDebt(String debtId);
}
