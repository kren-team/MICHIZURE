import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/app.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/debt/application/contribution_controller.dart';
import 'package:michizure/features/debt/application/debt_lock_release_controller.dart';
import 'package:michizure/features/recovery/application/recovery_controller.dart';
import 'package:michizure/features/task/application/handle_native_task_event.dart';

void main() {
  testWidgets('renders the login route for a signed-out user', (tester) async {
    final gate = AuthRouteGate();
    gate.update(const AsyncData(AuthRouteState.signedOut));
    final router = createAppRouter(authRouteGate: gate);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskGuardControllerProvider.overrideWithBuild(
            (ref, notifier) => const TaskGuardControllerState.idle(),
          ),
          debtLockReleaseControllerProvider.overrideWithBuild(
            (ref, notifier) => const DebtLockReleaseState.idle(),
          ),
          contributionControllerProvider.overrideWithBuild(
            (ref, notifier) => const ContributionControllerState.idle(),
          ),
          recoveryControllerProvider.overrideWithBuild(
            (ref, notifier) => const RecoveryControllerState.idle(),
          ),
        ],
        child: MichizureApp(
          bootstrapState: BootstrapState(
            environment: AppEnvironment.firebaseEmulator,
            projectId: demoFirebaseProjectId,
            startedAt: DateTime.utc(2026),
          ),
          router: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-submit-button')), findsOneWidget);
  });
}
