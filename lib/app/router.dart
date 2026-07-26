import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap.dart';

const String bootstrapRoutePath = '/';

GoRouter createAppRouter() => GoRouter(
  initialLocation: bootstrapRoutePath,
  routes: [
    GoRoute(
      path: bootstrapRoutePath,
      builder: (context, state) => const BootstrapScreen(),
    ),
  ],
);

final bootstrapStateProvider = Provider<BootstrapState>((ref) {
  throw StateError(
    'BootstrapState must be overridden at the application root.',
  );
});

final class BootstrapScreen extends ConsumerWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapStateProvider);
    final environmentLabel = switch (bootstrap.environment) {
      AppEnvironment.firebaseEmulator => 'Firebase Emulator',
      AppEnvironment.live => 'Live Firebase',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('MICHIZURE')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                'Bootstrap OK',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text('Environment: $environmentLabel'),
              Text('Project: ${bootstrap.projectId}'),
            ],
          ),
        ),
      ),
    );
  }
}
