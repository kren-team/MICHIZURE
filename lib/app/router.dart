import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/debt/presentation/debt_detail_screen.dart';
import '../features/debt/presentation/debt_list_screen.dart';
import '../features/debt/presentation/contribution_session_screen.dart';
import '../features/enforcement/presentation/app_selection/app_selection_screen.dart';
import '../features/enforcement/presentation/device_setup/device_setup_screen.dart';
import '../features/enforcement/presentation/lock_status/lock_status_screen.dart';
import '../features/group/presentation/group_create_screen.dart';
import '../features/group/presentation/group_home_screen.dart';
import '../features/group/presentation/group_invite_screen.dart';
import '../features/group/presentation/group_join_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import '../features/task/presentation/running_task_screen.dart';
import '../features/task/presentation/task_composer_screen.dart';
import 'providers.dart';

const String splashRoutePath = '/splash';
const String loginRoutePath = '/login';
const String registerRoutePath = '/register';
const String authenticatedRoutePath = '/home';
const String profileSetupRoutePath = '/profile-setup';
const String profileRoutePath = '/profile';
const String groupCreateRoutePath = '/group/create';
const String groupJoinRoutePath = '/group/join';
const String groupInviteRoutePath = '/group/invite';
const String deviceSetupRoutePath = '/device-setup';
const String appSelectionRoutePath = '/device-setup/apps';
const String lockStatusRoutePath = '/lock-status';
const String debtListRoutePath = '/debts';
const String taskComposerRoutePath = '/task/new';
const String runningTaskRoutePath = '/task/running';
const String recoverableErrorRoutePath = '/error';

enum AuthRouteState {
  loading,
  signedOut,
  profileSetup,
  ready,
  runningTask,
  recoverableError,
}

final class AuthRouteGate extends ChangeNotifier {
  AuthRouteState _state = AuthRouteState.loading;

  AuthRouteState get state => _state;

  void update(AsyncValue<AuthRouteState> state) {
    final nextState = switch (state) {
      AsyncLoading() => AuthRouteState.loading,
      AsyncError() => AuthRouteState.recoverableError,
      AsyncData(value: final value) => value,
    };

    if (nextState != _state) {
      _state = nextState;
      notifyListeners();
    }
  }
}

final authRouteGateProvider = Provider<AuthRouteGate>((ref) {
  final gate = AuthRouteGate();
  gate.update(ref.read(appRouteStateProvider));
  ref.listen<AsyncValue<AuthRouteState>>(
    appRouteStateProvider,
    (_, next) => gate.update(next),
  );
  ref.onDispose(gate.dispose);
  return gate;
});

final appRouteStateProvider = Provider<AsyncValue<AuthRouteState>>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    loading: () => const AsyncLoading(),
    error: (error, stackTrace) => AsyncError(error, stackTrace),
    data: (user) {
      if (user == null) {
        return const AsyncData(AuthRouteState.signedOut);
      }
      return ref
          .watch(currentProfileProvider)
          .when(
            loading: () => const AsyncLoading(),
            error: (error, stackTrace) => AsyncError(error, stackTrace),
            data: (profile) {
              if (profile == null) {
                return const AsyncData(AuthRouteState.profileSetup);
              }
              return AsyncData(
                profile.activeTaskSessionId == null
                    ? AuthRouteState.ready
                    : AuthRouteState.runningTask,
              );
            },
          );
    },
  );
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final gate = ref.watch(authRouteGateProvider);
  final router = createAppRouter(authRouteGate: gate);
  ref.onDispose(router.dispose);
  return router;
});

GoRouter createAppRouter({AuthRouteGate? authRouteGate}) {
  final gate = authRouteGate ?? AuthRouteGate();

  return GoRouter(
    initialLocation: splashRoutePath,
    refreshListenable: gate,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isAuthRoute =
          location == loginRoutePath || location == registerRoutePath;

      return switch (gate.state) {
        AuthRouteState.loading =>
          location == splashRoutePath ? null : splashRoutePath,
        AuthRouteState.signedOut => isAuthRoute ? null : loginRoutePath,
        AuthRouteState.profileSetup =>
          location == profileSetupRoutePath ? null : profileSetupRoutePath,
        AuthRouteState.ready =>
          location == splashRoutePath ||
                  isAuthRoute ||
                  location == profileSetupRoutePath ||
                  location == recoverableErrorRoutePath
              ? authenticatedRoutePath
              : null,
        AuthRouteState.runningTask =>
          location == runningTaskRoutePath ? null : runningTaskRoutePath,
        AuthRouteState.recoverableError =>
          location == recoverableErrorRoutePath
              ? null
              : recoverableErrorRoutePath,
      };
    },
    routes: [
      GoRoute(
        path: splashRoutePath,
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: loginRoutePath,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: registerRoutePath,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: authenticatedRoutePath,
        builder: (context, state) => const GroupHomeScreen(),
      ),
      GoRoute(
        path: profileSetupRoutePath,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: profileRoutePath,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: groupCreateRoutePath,
        builder: (context, state) => const GroupCreateScreen(),
      ),
      GoRoute(
        path: groupJoinRoutePath,
        builder: (context, state) => const GroupJoinScreen(),
      ),
      GoRoute(
        path: groupInviteRoutePath,
        builder: (context, state) => const GroupInviteScreen(),
      ),
      GoRoute(
        path: deviceSetupRoutePath,
        builder: (context, state) => const DeviceSetupScreen(),
      ),
      GoRoute(
        path: appSelectionRoutePath,
        builder: (context, state) => const AppSelectionScreen(),
      ),
      GoRoute(
        path: lockStatusRoutePath,
        builder: (context, state) => const LockStatusScreen(),
      ),
      GoRoute(
        path: debtListRoutePath,
        builder: (context, state) => const DebtListScreen(),
        routes: [
          GoRoute(
            path: ':debtId',
            builder: (context, state) =>
                DebtDetailScreen(debtId: state.pathParameters['debtId']!),
            routes: [
              GoRoute(
                path: 'repay',
                builder: (context, state) => ContributionSessionScreen(
                  debtId: state.pathParameters['debtId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: taskComposerRoutePath,
        builder: (context, state) => const TaskComposerScreen(),
      ),
      GoRoute(
        path: runningTaskRoutePath,
        builder: (context, state) => const RunningTaskScreen(),
      ),
      GoRoute(
        path: recoverableErrorRoutePath,
        builder: (context, state) => const RecoverableErrorScreen(),
      ),
    ],
  );
}

final class RecoverableErrorScreen extends ConsumerWidget {
  const RecoverableErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('状態を読み込めませんでした。'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('recoverable-error-retry-button'),
              onPressed: () {
                ref.invalidate(currentProfileProvider);
                ref.invalidate(authStateProvider);
              },
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
