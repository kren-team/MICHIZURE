import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/authenticated_placeholder_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import 'providers.dart';

const String splashRoutePath = '/splash';
const String loginRoutePath = '/login';
const String registerRoutePath = '/register';
const String authenticatedRoutePath = '/home';
const String profileSetupRoutePath = '/profile-setup';
const String profileRoutePath = '/profile';
const String recoverableErrorRoutePath = '/error';

enum AuthRouteState {
  loading,
  signedOut,
  profileSetup,
  ready,
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
            data: (profile) => AsyncData(
              profile == null
                  ? AuthRouteState.profileSetup
                  : AuthRouteState.ready,
            ),
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
                  location == profileSetupRoutePath
              ? authenticatedRoutePath
              : null,
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
        builder: (context, state) => const AuthenticatedPlaceholderScreen(),
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
        path: recoverableErrorRoutePath,
        builder: (context, state) => const _RecoverableErrorScreen(),
      ),
    ],
  );
}

final class _RecoverableErrorScreen extends StatelessWidget {
  const _RecoverableErrorScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('状態を読み込めませんでした。アプリを再起動してください。')),
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
