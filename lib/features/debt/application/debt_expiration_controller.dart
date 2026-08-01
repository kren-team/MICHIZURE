import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/debt.dart';
import '../domain/debt_failure.dart';

final debtExpirationControllerProvider =
    NotifierProvider<DebtExpirationController, AsyncValue<void>>(
      DebtExpirationController.new,
    );

final class DebtExpirationController extends Notifier<AsyncValue<void>> {
  final Set<String> _inFlightDebtIds = {};

  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> expireOverdue(Iterable<Debt> debts, DateTime now) async {
    final overdue = debts
        .where((debt) => debt.isOverdueAt(now))
        .map((debt) => debt.id)
        .where(_inFlightDebtIds.add)
        .toList(growable: false);
    if (overdue.isEmpty) {
      return;
    }
    state = const AsyncLoading();
    Object? firstFailure;
    StackTrace? firstStackTrace;
    for (final debtId in overdue) {
      try {
        await ref.read(debtRepositoryProvider).expireDebt(debtId);
      } on Object catch (error, stackTrace) {
        firstFailure ??= error is DebtFailure
            ? error
            : const DebtFailure(DebtFailureKind.unknown);
        firstStackTrace ??= stackTrace;
      } finally {
        _inFlightDebtIds.remove(debtId);
      }
    }
    if (!ref.mounted) {
      return;
    }
    if (firstFailure != null) {
      state = AsyncError(firstFailure, firstStackTrace ?? StackTrace.current);
    } else {
      state = const AsyncData(null);
    }
  }

  void clearFailure() {
    if (!state.isLoading) {
      state = const AsyncData(null);
    }
  }
}
