import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/debt/application/debt_lock_release_controller.dart';
import 'package:michizure/features/debt/domain/debt.dart';
import 'package:michizure/features/enforcement/domain/app_lock.dart';

import '../../enforcement/support/fake_app_lock_repository.dart';
import '../support/fake_debt_repository.dart';

void main() {
  test(
    'remote completed snapshot releases the matching obligation once',
    () async {
      final debtRepository = FakeDebtRepository();
      final lockRepository = FakeAppLockRepository()
        ..state = _lockState(['debt-a']);
      final container = _container(debtRepository, lockRepository);

      container.read(debtLockReleaseControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      debtRepository.debtControllers['debt-a']!.add(
        _snapshot(_debt('debt-a', DebtStatus.completed)),
      );
      debtRepository.debtControllers['debt-a']!.add(
        _snapshot(_debt('debt-a', DebtStatus.completed)),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(lockRepository.releaseCalls, 1);
      expect(lockRepository.lastReleasedDebtId, 'debt-a');
      expect(lockRepository.lastResolution, LockRemoteStatus.completed);
    },
  );

  test(
    'one terminal Debt does not release another active obligation',
    () async {
      final debtRepository = FakeDebtRepository();
      final lockRepository = FakeAppLockRepository()
        ..state = _lockState(['debt-a', 'debt-b']);
      final container = _container(debtRepository, lockRepository);

      container.read(debtLockReleaseControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      debtRepository.debtControllers['debt-a']!.add(
        _snapshot(_debt('debt-a', DebtStatus.expired)),
      );
      debtRepository.debtControllers['debt-b']!.add(
        _snapshot(_debt('debt-b', DebtStatus.active)),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(lockRepository.releaseCalls, 1);
      expect(lockRepository.lastReleasedDebtId, 'debt-a');
      expect(lockRepository.lastResolution, LockRemoteStatus.expired);
    },
  );

  test(
    'native release failure is typed and retried by a later snapshot',
    () async {
      final debtRepository = FakeDebtRepository();
      final lockRepository = FakeAppLockRepository()
        ..state = _lockState(['debt-a'])
        ..releaseError = StateError('native detail must not escape');
      final container = _container(debtRepository, lockRepository);

      container.read(debtLockReleaseControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      debtRepository.debtControllers['debt-a']!.add(
        _snapshot(_debt('debt-a', DebtStatus.completed)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(debtLockReleaseControllerProvider).failure?.kind.name,
        'nativeReleaseFailed',
      );
    },
  );
}

ProviderContainer _container(
  FakeDebtRepository debtRepository,
  FakeAppLockRepository lockRepository,
) {
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWithValue(
        const AsyncData(AuthUser(id: 'alice')),
      ),
      debtRepositoryProvider.overrideWithValue(debtRepository),
      appLockRepositoryProvider.overrideWithValue(lockRepository),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await debtRepository.dispose();
  });
  return container;
}

DebtSnapshot<Debt?> _snapshot(Debt debt) {
  return DebtSnapshot(value: debt, isFromCache: false, hasPendingWrites: false);
}

Debt _debt(String id, DebtStatus status) {
  final isCompleted = status == DebtStatus.completed;
  return Debt(
    id: id,
    groupId: 'group-1',
    failedUserId: 'alice',
    failedTaskSessionId: id,
    memberCountAtFailure: 2,
    repsPerMember: 10,
    totalReps: 20,
    completedReps: isCompleted ? 20 : 0,
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
    lockExpiresAt: DateTime.utc(2026, 1, 1, 0, 30),
    closedAt: status == DebtStatus.active
        ? null
        : DateTime.utc(2026, 1, 1, 0, 20),
    lastContributionAt: null,
    lastContributionEventId: null,
  );
}

AppLockState _lockState(List<String> debtIds) {
  return AppLockState(
    obligations: debtIds
        .map(
          (id) => LockObligationSummary(
            debtId: id,
            taskSessionId: id,
            expiresAt: DateTime.utc(2026, 1, 1, 0, 30),
            remoteStatus: LockRemoteStatus.active,
            localState: LockLocalState.enforced,
            targetCount: 1,
            enforcedCount: 1,
            failedCount: 0,
            errorCode: null,
          ),
        )
        .toList(),
    effectiveTargetCount: 1,
    ownedSuspensionCount: 1,
    appliedCount: 0,
    releasedCount: 0,
    failedCount: 0,
    nextDeadline: DateTime.utc(2026, 1, 1, 0, 30),
  );
}
