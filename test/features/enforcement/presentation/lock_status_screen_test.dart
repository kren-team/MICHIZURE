import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/enforcement/domain/app_lock.dart';
import 'package:michizure/features/enforcement/presentation/lock_status/lock_status_screen.dart';

import '../support/fake_app_lock_repository.dart';

void main() {
  testWidgets('shows overlapping lock obligations and partial failure', (
    tester,
  ) async {
    final repository = FakeAppLockRepository()
      ..state = AppLockState(
        obligations: [
          _obligation('debt-a', failedCount: 0),
          _obligation('debt-b', failedCount: 1),
        ],
        effectiveTargetCount: 2,
        ownedSuspensionCount: 1,
        appliedCount: 1,
        releasedCount: 0,
        failedCount: 1,
        nextDeadline: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: LockStatusScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('アプリを封印中'), findsOneWidget);
    expect(
      find.byKey(const Key('lock-partial-failure-message')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('lock-obligation-debt-a')), findsOneWidget);
    expect(find.byKey(const Key('lock-obligation-debt-b')), findsOneWidget);
    expect(find.textContaining('すべて解決するまで'), findsOneWidget);
  });
}

LockObligationSummary _obligation(String debtId, {required int failedCount}) {
  return LockObligationSummary(
    debtId: debtId,
    taskSessionId: 'task-$debtId',
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    remoteStatus: LockRemoteStatus.active,
    localState: failedCount == 0
        ? LockLocalState.enforced
        : LockLocalState.degraded,
    targetCount: 1,
    enforcedCount: failedCount == 0 ? 1 : 0,
    failedCount: failedCount,
    errorCode: failedCount == 0 ? null : 'suspensionPartialFailure',
  );
}
