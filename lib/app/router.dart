import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/domain/auth_user.dart';
import '../features/auth/presentation/authenticated_placeholder_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import 'providers.dart';

const String splashRoutePath = '/splash';
const String loginRoutePath = '/login';
const String registerRoutePath = '/register';
const String authenticatedRoutePath = '/home';

enum AuthRouteState { loading, signedOut, signedIn }

final class AuthRouteGate extends ChangeNotifier {
  AuthRouteState _state = AuthRouteState.loading;

  AuthRouteState get state => _state;

  void update(AsyncValue<AuthUser?> authState) {
    final nextState = switch (authState) {
      AsyncLoading() => AuthRouteState.loading,
      AsyncError() => AuthRouteState.signedOut,
      AsyncData(value: null) => AuthRouteState.signedOut,
      AsyncData() => AuthRouteState.signedIn,
    };

    if (nextState != _state) {
      _state = nextState;
      notifyListeners();
    }
  }
}

final authRouteGateProvider = Provider<AuthRouteGate>((ref) {
  final gate = AuthRouteGate();
  gate.update(ref.read(authStateProvider));
  ref.listen<AsyncValue<AuthUser?>>(
    authStateProvider,
    (_, next) => gate.update(next),
  );
  ref.onDispose(gate.dispose);
  return gate;
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
        AuthRouteState.signedIn =>
          location == splashRoutePath || isAuthRoute
              ? authenticatedRoutePath
              : null,
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
    ],
  );
}

final class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
