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
}
