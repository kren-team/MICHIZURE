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
          child: Text(
            enforcementFailureMessage(error),
            key: const Key('app-selection-load-error'),
          ),
        ),
        data: (state) {
          if (state.apps.isEmpty) {
            return const Center(child: Text('選択できるアプリが見つかりません。'));
          }
          return Column(
            children: [
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
                                const SnackBar(content: Text('封印対象を保存しました')),
                              );
                            }
                          },
                    child: state.isSaving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('${state.selectedPackageNames.length}件を保存'),
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
