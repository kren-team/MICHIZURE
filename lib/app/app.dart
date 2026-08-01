import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/presentation/app_theme.dart';
import '../features/debt/application/contribution_controller.dart';
import '../features/debt/application/debt_lock_release_controller.dart';
import '../features/notifications/application/device_registration_controller.dart';
import '../features/notifications/application/notification_navigation_coordinator.dart';
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
  final NotificationNavigationCoordinator _notificationNavigation =
      NotificationNavigationCoordinator();

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
        if (previous?.navigationSequence == next.navigationSequence) {
          return;
        }
        final message = next.navigationMessage;
        if (message == null) {
          return;
        }
        _notificationNavigation.enqueue(message);
        _scheduleNotificationNavigation(router);
      });
      ref.listen(appRouteStateProvider, (_, _) {
        _scheduleNotificationNavigation(router);
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

  void _scheduleNotificationNavigation(GoRouter router) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final routeState = ref.read(appRouteStateProvider).value;
      final path = _notificationNavigation.takeNextPath(
        canNavigate: routeState == AuthRouteState.ready,
      );
      if (path != null) {
        router.go(path);
      }
    });
  }
}
