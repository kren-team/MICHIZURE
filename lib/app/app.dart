import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/debt/application/contribution_controller.dart';
import '../features/debt/application/debt_lock_release_controller.dart';
import '../features/recovery/application/recovery_controller.dart';
import '../features/recovery/domain/recovery.dart';
import '../features/recovery/presentation/recovery_status_overlay.dart';
import '../features/task/application/handle_native_task_event.dart';
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

final class _MichizureAppView extends ConsumerStatefulWidget {
  const _MichizureAppView();

  @override
  ConsumerState<_MichizureAppView> createState() => _MichizureAppViewState();
}

final class _MichizureAppViewState extends ConsumerState<_MichizureAppView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
          .read(recoveryControllerProvider.notifier)
          .recover(RecoveryTrigger.foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(taskGuardControllerProvider);
    ref.watch(debtLockReleaseControllerProvider);
    ref.watch(contributionControllerProvider);
    ref.watch(recoveryControllerProvider);
    return MaterialApp.router(
      title: 'MICHIZURE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) =>
          RecoveryStatusOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
