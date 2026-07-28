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
      appBar: AppBar(title: const Text('Device Setup')),
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
              const Text(
                '強制封印は、adbでDevice Ownerに設定したハッカソン用managed Emulatorだけで利用できます。',
              ),
              const SizedBox(height: 20),
              _CapabilityTile(
                key: const Key('device-owner-capability'),
                title: 'Device Owner',
                ready: state.capabilities.isDeviceOwner,
                detail: state.capabilities.isDeviceOwner
                    ? 'Managed demoとして認識されています'
                    : 'アプリ自身では取得できません。PCからadb provisioningが必要です',
              ),
              _CapabilityTile(
                key: const Key('usage-access-capability'),
                title: 'Usage Access',
                ready: state.capabilities.hasUsageAccess,
                detail: state.capabilities.hasUsageAccess
                    ? '利用状況へのアクセスが許可されています'
                    : '離脱検知には設定画面での許可が必要です',
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
                    ? '通知を表示できます'
                    : '後続Phaseの監視通知に許可が必要です',
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
                    ? 'debug buildのデモ用一覧を利用できます'
                    : '公開buildではAndroidのscoped visibilityに限定されます',
              ),
              _CapabilityTile(
                title: 'Android enforcement API',
                ready:
                    state.capabilities.supportsHardEnforcement &&
                    state.capabilities.isUserUnlocked,
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
