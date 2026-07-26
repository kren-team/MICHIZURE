import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap.dart';
import 'router.dart';

final class MichizureApp extends StatelessWidget {
  MichizureApp({required this.bootstrapState, GoRouter? router, super.key})
    : router = router ?? createAppRouter();

  final BootstrapState bootstrapState;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [bootstrapStateProvider.overrideWithValue(bootstrapState)],
      child: MaterialApp.router(
        title: 'MICHIZURE',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}
