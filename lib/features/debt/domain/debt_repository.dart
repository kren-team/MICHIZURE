import 'debt.dart';

abstract interface class DebtRepository {
  Stream<Debt?> watchDebt(String debtId);
}
