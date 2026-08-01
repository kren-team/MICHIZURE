import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/auth/presentation/login_screen.dart';
import 'package:michizure/features/debt/presentation/debt_detail_screen.dart';
import 'package:michizure/features/group/presentation/group_home_screen.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';
import 'package:michizure/features/profile/presentation/profile_setup_screen.dart';
import 'package:michizure/features/task/presentation/running_task_screen.dart';

import '../features/task/support/fake_task_repository.dart';
import '../features/task/support/fake_native_task_guard.dart';

void main() {
  group('route state matrix', () {
    testWidgets('loading stays on splash without redirecting in a loop', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, AuthRouteState.loading);

      expect(harness.location, splashRoutePath);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      harness.gate.update(const AsyncData(AuthRouteState.loading));
      await tester.pump();
      expect(harness.location, splashRoutePath);
    });

    testWidgets('signedOut redirects to Login', (tester) async {
      final harness = await _pumpRouter(tester, AuthRouteState.signedOut);

      expect(harness.location, loginRoutePath);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signedIn without a profile redirects to Profile Setup', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, AuthRouteState.profileSetup);

      expect(harness.location, profileSetupRoutePath);
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
    });

    testWidgets('signedIn with a profile redirects to Home', (tester) async {
      final harness = await _pumpRouter(tester, AuthRouteState.ready);

      expect(harness.location, authenticatedRoutePath);
      expect(find.byType(GroupHomeScreen), findsOneWidget);
    });

    testWidgets('a restored active Task redirects to Running Task', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, AuthRouteState.runningTask);

      expect(harness.location, runningTaskRoutePath);
      expect(find.byType(RunningTaskScreen), findsOneWidget);
    });

    testWidgets('created Debt route keeps its extra during Task gate refresh', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, AuthRouteState.runningTask);
      final debt = debtFixture();

      harness.router.go('/debts/${debt.id}', extra: debt);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(harness.location, '/debts/${debt.id}');
      expect(find.byType(DebtDetailScreen), findsOneWidget);

      harness.gate.update(const AsyncData(AuthRouteState.ready));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(harness.location, '/debts/${debt.id}');
      expect(find.byType(DebtDetailScreen), findsOneWidget);
    });

    testWidgets(
      'Debt route without created Debt extra stays behind Task gate',
      (tester) async {
        final harness = await _pumpRouter(tester, AuthRouteState.runningTask);

        harness.router.go('/debts/task-1');
        await tester.pump();

        expect(harness.location, runningTaskRoutePath);
        expect(find.byType(RunningTaskScreen), findsOneWidget);
      },
    );

    testWidgets('recoverable error automatically returns to Home when ready', (
      tester,
    ) async {
      final harness = await _pumpRouter(
        tester,
        AuthRouteState.recoverableError,
      );
      expect(harness.location, recoverableErrorRoutePath);
      expect(find.byType(RecoverableErrorScreen), findsOneWidget);

      harness.gate.update(const AsyncData(AuthRouteState.ready));
      await tester.pumpAndSettle();

      expect(harness.location, authenticatedRoutePath);
      expect(find.byType(GroupHomeScreen), findsOneWidget);
    });

    testWidgets('recoverable error returns to Profile Setup when missing', (
      tester,
    ) async {
      final harness = await _pumpRouter(
        tester,
        AuthRouteState.recoverableError,
      );

      harness.gate.update(const AsyncData(AuthRouteState.profileSetup));
      await tester.pumpAndSettle();

      expect(harness.location, profileSetupRoutePath);
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
    });

    testWidgets('recoverable error returns to Login when signed out', (
      tester,
    ) async {
      final harness = await _pumpRouter(
        tester,
        AuthRouteState.recoverableError,
      );

      harness.gate.update(const AsyncData(AuthRouteState.signedOut));
      await tester.pumpAndSettle();

      expect(harness.location, loginRoutePath);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('logout redirects Home to Login', (tester) async {
      final harness = await _pumpRouter(tester, AuthRouteState.ready);
      expect(harness.location, authenticatedRoutePath);

      harness.gate.update(const AsyncData(AuthRouteState.signedOut));
      await tester.pumpAndSettle();

      expect(harness.location, loginRoutePath);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester,
  AuthRouteState initialState,
) async {
  final gate = AuthRouteGate();
  gate.update(AsyncData(initialState));
  final router = createAppRouter(authRouteGate: gate);
  final guard = FakeNativeTaskGuard();
  addTearDown(router.dispose);
  addTearDown(guard.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'alice')),
        ),
        currentProfileProvider.overrideWith((ref) => Stream.value(_profile)),
        activeTaskSessionProvider.overrideWith(
          (ref) => Stream.value(runningTaskFixture()),
        ),
        debtProvider('task-1').overrideWithValue(const AsyncLoading()),
        debtContributionsProvider(
          'task-1',
        ).overrideWithValue(const AsyncLoading()),
        nativeTaskGuardProvider.overrideWithValue(guard),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (initialState == AuthRouteState.loading) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }

  return _RouterHarness(gate: gate, router: router);
}

final class _RouterHarness {
  const _RouterHarness({required this.gate, required this.router});

  final AuthRouteGate gate;
  final GoRouter router;

  String get location => router.routerDelegate.currentConfiguration.uri.path;
}

final _profile = UserProfile(
  id: 'alice',
  displayName: 'Alice',
  photoUrl: null,
  groupId: null,
  activeTaskSessionId: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
