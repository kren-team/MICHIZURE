import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/presentation/app_theme.dart';
import '../features/debt/application/contribution_controller.dart';
import '../features/debt/application/debt_lock_release_controller.dart';
import '../features/notifications/application/device_registration_controller.dart';
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
    final router = ref.watch(appRouterProvider);
    ref.watch(taskGuardControllerProvider);
    ref.watch(debtLockReleaseControllerProvider);
    ref.watch(contributionControllerProvider);
    ref.watch(recoveryControllerProvider);
    if (Firebase.apps.isNotEmpty) {
      ref.watch(deviceRegistrationControllerProvider);
      ref.listen(deviceRegistrationControllerProvider, (previous, next) {
        if (previous?.messageSequence == next.messageSequence) {
          return;
        }
        final message = next.foregroundMessage;
        if (message == null) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final notificationContext =
              router.routerDelegate.navigatorKey.currentContext;
          final messenger = notificationContext == null
              ? null
              : ScaffoldMessenger.maybeOf(notificationContext);
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('${message.title}\n${message.body}')),
            );
        });
      });
    }
    return MaterialApp.router(
      title: 'MICHIZURE',
      theme: buildMichizureTheme(),
      routerConfig: router,
      builder: (context, child) =>
          RecoveryStatusOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
