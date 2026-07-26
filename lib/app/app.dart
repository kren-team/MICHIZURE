import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap.dart';
import 'router.dart';

final class MichizureApp extends StatelessWidget {
  const MichizureApp({required this.bootstrapState, this.router, super.key});

  final BootstrapState bootstrapState;
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (router case final router?)
          appRouterProvider.overrideWithValue(router),
      ],
      child: const _MichizureAppView(),
    );
  }
}

final class _MichizureAppView extends ConsumerWidget {
  const _MichizureAppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MICHIZURE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
