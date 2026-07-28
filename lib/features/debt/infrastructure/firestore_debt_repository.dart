import 'package:cloud_firestore/cloud_firestore.dart';

import '../../task/infrastructure/firestore_task_repository.dart';
import '../domain/debt.dart';
import '../domain/debt_repository.dart';

final class FirestoreDebtRepository implements DebtRepository {
  FirestoreDebtRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<Debt?> watchDebt(String debtId) {
    return _firestore.collection('debts').doc(debtId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }
      return debtFromFirestore(snapshot.id, snapshot.data()!);
    });
  }
}
