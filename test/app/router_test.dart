import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/router.dart';
import 'package:michizure/features/auth/presentation/login_screen.dart';

void main() {
  testWidgets('router sends a signed-out user to login', (tester) async {
    final gate = AuthRouteGate();
    gate.update(const AsyncData(AuthRouteState.signedOut));
    final router = createAppRouter(authRouteGate: gate);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();

    expect(router.routerDelegate.currentConfiguration.uri.path, loginRoutePath);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
