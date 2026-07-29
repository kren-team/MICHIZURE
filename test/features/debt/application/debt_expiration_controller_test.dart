import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/debt/application/debt_expiration_controller.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/debt/domain/debt_failure.dart';

import '../support/fake_debt_repository.dart';

void main() {
  test(
    'only overdue active debts are submitted for server expiration',
    () async {
      final repository = FakeDebtRepository()
        ..expireResult = _debt(
          id: 'overdue',
          status: DebtStatus.expired,
          expiresAt: DateTime.utc(2026, 1, 1),
        );
      final container = ProviderContainer(
        overrides: [debtRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      await container
          .read(debtExpirationControllerProvider.notifier)
          .expireOverdue([
            _debt(id: 'future', expiresAt: DateTime.utc(2026, 1, 1, 11)),
            _debt(id: 'overdue', expiresAt: DateTime.utc(2026, 1, 1, 9)),
          ], DateTime.utc(2026, 1, 1, 10));

      expect(repository.expiredDebtIds, ['overdue']);
    },
  );

  test('offline transaction failure remains typed', () async {
    final repository = FakeDebtRepository()
      ..expireError = const DebtFailure(DebtFailureKind.offline);
    final container = ProviderContainer(
      overrides: [debtRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() async {
      container.dispose();
      await repository.dispose();
    });

    await container
        .read(debtExpirationControllerProvider.notifier)
        .expireOverdue([
          _debt(id: 'overdue', expiresAt: DateTime.utc(2026, 1, 1, 9)),
        ], DateTime.utc(2026, 1, 1, 10));

    expect(
      container.read(debtExpirationControllerProvider).error,
      const DebtFailure(DebtFailureKind.offline),
    );
  });
}

Debt _debt({
  required String id,
  required DateTime expiresAt,
  DebtStatus status = DebtStatus.active,
}) {
  return Debt(
    id: id,
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: id,
    memberCountAtFailure: 1,
    repsPerMember: 10,
    totalReps: 10,
    completedReps: 0,
    status: status,
    createdAt: DateTime.utc(2025, 12, 31),
    lockExpiresAt: expiresAt,
    closedAt: status == DebtStatus.active ? null : expiresAt,
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}
