import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/device_setup_controller.dart';
import '../../domain/device_capabilities.dart';
import '../enforcement_failure_message.dart';

final class DeviceSetupScreen extends ConsumerStatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  ConsumerState<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

final class _DeviceSetupScreenState extends ConsumerState<DeviceSetupScreen>
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
      ref.read(deviceSetupControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(deviceSetupControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('端末セットアップ'),
        actions: [
          IconButton(
            tooltip: '端末状態を再確認',
            onPressed: () =>
                ref.read(deviceSetupControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: setup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _LoadError(
          error: error,
          onRetry: () =>
              ref.read(deviceSetupControllerProvider.notifier).refresh(),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: () =>
              ref.read(deviceSetupControllerProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                state.capabilities.isManagedDemoReady
                    ? 'デモ端末の準備ができています'
                    : 'タスク開始前に端末の準備が必要です',
                key: const Key('device-setup-summary'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('封印機能は、開発者が準備したハッカソン用の管理端末で利用できます。'),
              const SizedBox(height: 20),
              _CapabilityTile(
                key: const Key('device-owner-capability'),
                title: '管理端末',
                ready: state.capabilities.isDeviceOwner,
                detail: state.capabilities.isDeviceOwner
                    ? 'デモ用の管理端末として準備済みです'
                    : 'この設定はアプリ内では変更できません。デモ担当者へ確認してください',
              ),
              _CapabilityTile(
                key: const Key('usage-access-capability'),
                title: '利用状況へのアクセス',
                ready: state.capabilities.hasUsageAccess,
                detail: state.capabilities.hasUsageAccess
                    ? '別アプリへの移動を端末内で検知できます'
                    : '約束中の別アプリ移動を検知するため許可が必要です',
                actionLabel: state.capabilities.hasUsageAccess ? null : '設定を開く',
                onAction: () => ref
                    .read(deviceSetupControllerProvider.notifier)
                    .openUsageAccessSettings(),
              ),
              _CapabilityTile(
                key: const Key('notification-capability'),
                title: '通知',
                ready: state.capabilities.hasNotificationPermission,
                detail: state.capabilities.hasNotificationPermission
                    ? '約束の監視中であることを通知できます'
                    : '約束の監視中であることを表示するため許可が必要です',
                actionLabel: state.capabilities.hasNotificationPermission
                    ? null
                    : '設定を開く',
                onAction: () => ref
                    .read(deviceSetupControllerProvider.notifier)
                    .openNotificationSettings(),
              ),
              _CapabilityTile(
                key: const Key('package-visibility-capability'),
                title: 'アプリ一覧',
                ready:
                    state.capabilities.packageVisibility ==
                    PackageVisibility.broad,
                detail:
                    state.capabilities.packageVisibility ==
                        PackageVisibility.broad
                    ? 'デモ用のアプリ一覧を利用できます'
                    : '公開buildではAndroidのscoped visibilityに限定されます',
              ),
              _CapabilityTile(
                key: const Key('user-unlocked-capability'),
                title: '端末のロック解除',
                ready: state.capabilities.isUserUnlocked,
                detail: state.capabilities.isUserUnlocked
                    ? '端末内の復元データを利用できます'
                    : '端末のロックを解除してから再確認してください',
              ),
              _CapabilityTile(
                title: '封印機能',
                ready: state.capabilities.supportsHardEnforcement,
                detail: 'Android API ${state.capabilities.sdkInt}',
              ),
              if (state.commandFailure case final failure?) ...[
                const SizedBox(height: 12),
                Text(
                  enforcementFailureMessage(failure),
                  key: const Key('device-setup-command-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('app-selection-route-button'),
                onPressed: () => context.go('/device-setup/apps'),
                icon: const Icon(Icons.apps),
                label: Text('封印対象アプリを選ぶ（${state.savedPackageNames.length}件）'),
              ),
              if (state.capabilities.isManagedDemoReady &&
                  state.savedPackageNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('device-setup-task-route-button'),
                  onPressed: () => context.go('/task/new'),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('約束の設定へ進む'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.title,
    required this.ready,
    required this.detail,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final bool ready;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          ready ? Icons.check_circle : Icons.warning_amber,
          color: ready ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        title: Text(title),
        subtitle: Text(detail),
        trailing: actionLabel == null
            ? null
            : TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ),
    );
  }
}

final class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              enforcementFailureMessage(error),
              key: const Key('device-setup-load-error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}
