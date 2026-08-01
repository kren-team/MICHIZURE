import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/enforcement/application/app_lock_controller.dart';
import 'package:michizure/features/enforcement/domain/app_lock.dart';

import '../support/fake_app_lock_repository.dart';

void main() {
  test('reconcile is single-flight and publishes the native result', () async {
    final completer = Completer<AppLockState>();
    final repository = FakeAppLockRepository()..reconcileCompleter = completer;
    final container = _container(repository);
    await container.read(appLockControllerProvider.future);
    final controller = container.read(appLockControllerProvider.notifier);

    final first = controller.reconcile();
    final duplicate = controller.reconcile();

    expect(repository.reconcileCalls, 1);
    expect(await duplicate, isFalse);
    completer.complete(_activeState());
    expect(await first, isTrue);
    expect(
      container.read(appLockControllerProvider).requireValue.hasActiveLock,
      isTrue,
    );
  });

  test('release forwards the stable Debt ID and terminal resolution', () async {
    final repository = FakeAppLockRepository();
    final container = _container(repository);
    await container.read(appLockControllerProvider.future);

    final result = await container
        .read(appLockControllerProvider.notifier)
        .release(debtId: 'debt-1', resolution: LockRemoteStatus.expired);

    expect(result, isTrue);
    expect(repository.releaseCalls, 1);
    expect(repository.lastReleasedDebtId, 'debt-1');
    expect(repository.lastResolution, LockRemoteStatus.expired);
  });
}

ProviderContainer _container(FakeAppLockRepository repository) {
  final container = ProviderContainer(
    overrides: [appLockRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

AppLockState _activeState() {
  return AppLockState(
    obligations: [
      LockObligationSummary(
        debtId: 'debt-1',
        taskSessionId: 'task-1',
        expiresAt: DateTime.utc(2026, 7, 29, 12),
        remoteStatus: LockRemoteStatus.active,
        localState: LockLocalState.enforced,
        targetCount: 1,
        enforcedCount: 1,
        failedCount: 0,
        errorCode: null,
      ),
    ],
    effectiveTargetCount: 1,
    ownedSuspensionCount: 1,
    appliedCount: 1,
    releasedCount: 0,
    failedCount: 0,
    nextDeadline: DateTime.utc(2026, 7, 29, 12),
  );
}
