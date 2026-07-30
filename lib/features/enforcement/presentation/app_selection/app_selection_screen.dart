import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/device_setup_controller.dart';
import '../../domain/lockable_app.dart';
import '../enforcement_failure_message.dart';

final class AppSelectionScreen extends ConsumerWidget {
  const AppSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(deviceSetupControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('封印対象アプリ')),
      body: setup.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enforcementFailureMessage(error),
                  key: const Key('app-selection-load-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('app-selection-retry-button'),
                  onPressed: () => ref
                      .read(deviceSetupControllerProvider.notifier)
                      .refresh(),
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
        data: (state) {
          if (state.apps.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.apps_outage, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Launcherから起動できるアプリが見つかりません。',
                      key: Key('app-selection-empty'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text('対象アプリをインストールした後、一覧を再読み込みしてください。'),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('app-selection-empty-retry-button'),
                      onPressed: () => ref
                          .read(deviceSetupControllerProvider.notifier)
                          .refresh(),
                      child: const Text('一覧を再読み込み'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              if (!state.capabilities.isDeviceOwner)
                const Material(
                  color: Colors.amberAccent,
                  child: ListTile(
                    leading: Icon(Icons.warning_amber),
                    title: Text('管理端末の準備が必要です'),
                    subtitle: Text('アプリは選択できますが、封印の実行にはDevice Owner設定が必要です。'),
                  ),
                ),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: ListTile(
                  key: const Key('app-selection-summary'),
                  leading: const Icon(Icons.lock_outline),
                  title: Text('${state.selectedPackageNames.length}件を選択中'),
                  subtitle: Text(
                    state.hasUnsavedChanges
                        ? '変更はまだ端末に保存されていません'
                        : '選択内容はこの端末だけに保存されています',
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: state.apps.length,
                  itemBuilder: (context, index) {
                    final app = state.apps[index];
                    final selected = state.selectedPackageNames.contains(
                      app.packageName,
                    );
                    return CheckboxListTile(
                      key: Key('app-selection-${app.packageName}'),
                      value: selected,
                      onChanged: app.isSelectable && !state.isSaving
                          ? (value) => ref
                                .read(deviceSetupControllerProvider.notifier)
                                .togglePackage(
                                  app.packageName,
                                  selected: value ?? false,
                                )
                          : null,
                      secondary: const Icon(Icons.android),
                      title: Text(app.label),
                      subtitle: Text(
                        app.isSelectable
                            ? '失敗時にこのアプリを封印できます'
                            : _protectedReasonMessage(app.protectionReason),
                      ),
                    );
                  },
                ),
              ),
              if (state.commandFailure case final failure?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    enforcementFailureMessage(failure),
                    key: const Key('app-selection-save-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('app-selection-save-button'),
                    onPressed: state.isSaving || !state.hasUnsavedChanges
                        ? null
                        : () async {
                            final saved = await ref
                                .read(deviceSetupControllerProvider.notifier)
                                .save();
                            if (saved && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('選択を保存しました')),
                              );
                            }
                          },
                    child: state.isSaving
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('保存しています…'),
                            ],
                          )
                        : const Text('選択を保存'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _protectedReasonMessage(PackageProtectionReason? reason) {
  return switch (reason) {
    PackageProtectionReason.self => 'MICHIZURE自身は選択できません',
    PackageProtectionReason.deviceAdmin => 'Device Adminは選択できません',
    PackageProtectionReason.launcher => 'Launcherは選択できません',
    PackageProtectionReason.dialer => '既定の電話アプリは選択できません',
    PackageProtectionReason.permissionController => '権限管理アプリは選択できません',
    PackageProtectionReason.settings => '端末設定は選択できません',
    PackageProtectionReason.packageManager => 'アプリ管理機能は選択できません',
    null => 'Androidにより保護されています',
  };
}
