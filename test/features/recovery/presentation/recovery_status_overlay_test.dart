import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/recovery/application/recovery_controller.dart';
import 'package:michizure/features/recovery/domain/recovery.dart';
import 'package:michizure/features/recovery/presentation/recovery_status_overlay.dart';

void main() {
  testWidgets('shows a non-blocking progress indicator while recovering', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryControllerProvider.overrideWithBuild(
            (ref, notifier) => const RecoveryControllerState(
              phase: RecoveryPhase.reconcilingRemote,
              trigger: RecoveryTrigger.coldStart,
            ),
          ),
        ],
        child: const MaterialApp(
          home: RecoveryStatusOverlay(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(
      find.byKey(const Key('recovery-progress-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('shows a safe diagnostic without SDK details', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recoveryControllerProvider.overrideWithBuild(
            (ref, notifier) => const RecoveryControllerState(
              phase: RecoveryPhase.actionRequired,
              trigger: RecoveryTrigger.coldStart,
            ),
          ),
        ],
        child: const MaterialApp(
          home: RecoveryStatusOverlay(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );

    expect(find.byKey(const Key('recovery-status-card')), findsOneWidget);
    expect(find.text('端末またはアカウント状態の確認が必要です。'), findsOneWidget);
    expect(find.textContaining('FirebaseException'), findsNothing);
  });

  testWidgets('warning has a close button and stays dismissed', (tester) async {
    await tester.pumpWidget(_warningApp());

    expect(find.byKey(const Key('recovery-close-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('recovery-close-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('recovery-status-card')), findsNothing);
  });

  testWidgets('body remains tappable while warning is visible', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _warningApp(
        child: Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('body-action'),
              onPressed: () => taps += 1,
              child: const Text('本文の操作'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('body-action')));

    expect(taps, 1);
    expect(find.byKey(const Key('recovery-status-card')), findsOneWidget);
  });

  testWidgets('same warning is rendered only once after rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(_warningApp());
    await tester.pumpWidget(_warningApp());

    expect(find.byKey(const Key('recovery-status-card')), findsOneWidget);
    expect(find.text('一部の同期を保留しています。通信状態を確認してください。'), findsOneWidget);
  });

  testWidgets('retry invokes its callback exactly once', (tester) async {
    var retries = 0;
    await tester.pumpWidget(_warningApp(onRetry: () => retries += 1));

    await tester.tap(find.byKey(const Key('recovery-retry-button')));
    await tester.pump();

    expect(retries, 1);
  });
}

Widget _warningApp({Widget? child, VoidCallback? onRetry}) {
  return ProviderScope(
    overrides: [
      recoveryControllerProvider.overrideWithBuild(
        (ref, notifier) => const RecoveryControllerState(
          phase: RecoveryPhase.degraded,
          trigger: RecoveryTrigger.coldStart,
        ),
      ),
    ],
    child: MaterialApp(
      home: RecoveryStatusOverlay(
        onRetry: onRetry,
        child: child ?? const Scaffold(body: Text('Home')),
      ),
    ),
  );
}
