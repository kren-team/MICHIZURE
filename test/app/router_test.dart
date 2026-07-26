import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/bootstrap.dart';
import 'package:michizure/app/router.dart';

void main() {
  testWidgets('router starts at the bootstrap route', (tester) async {
    final router = createAppRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapStateProvider.overrideWithValue(
            BootstrapState(
              environment: AppEnvironment.firebaseEmulator,
              projectId: demoFirebaseProjectId,
              startedAt: DateTime.utc(2026),
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      bootstrapRoutePath,
    );
  });
}
