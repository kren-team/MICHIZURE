import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../enforcement/application/device_setup_controller.dart';
import '../application/task_command_controller.dart';
import '../domain/task_session.dart';
import 'task_failure_message.dart';

final class TaskComposerScreen extends ConsumerStatefulWidget {
  const TaskComposerScreen({super.key});

  @override
  ConsumerState<TaskComposerScreen> createState() => _TaskComposerScreenState();
}

final class _TaskComposerScreenState extends ConsumerState<TaskComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  int _durationMinutes = 30;

  static const _durationOptions = [1, 5, 15, 30, 60, 90, 180];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(taskCommandControllerProvider.notifier).clear(),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final authUser = ref.watch(authStateProvider).value;
    final command = ref.watch(taskCommandControllerProvider);
    final deviceSetup = ref.watch(deviceSetupControllerProvider);
    final setup = deviceSetup.value;
    final isReadyToStart =
        setup?.capabilities.isManagedDemoReady == true &&
        setup!.savedPackageNames.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('約束を始める')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('task-content-field'),
                  controller: _contentController,
                  maxLength: TaskContentValidator.maximumLength,
                  decoration: const InputDecoration(
                    labelText: '約束の内容',
                    hintText: '例：勉強する',
                  ),
                  validator: (value) =>
                      TaskContentValidator.isValid(value ?? '')
                      ? null
                      : '1〜100文字で入力してください',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('task-duration-field'),
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(labelText: '実行時間'),
                  items: _durationOptions
                      .map(
                        (minutes) => DropdownMenuItem(
                          value: minutes,
                          child: Text('$minutes分'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: command.isLoading
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _durationMinutes = value);
                          }
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('約束中はMICHIZUREに留まってください'),
              subtitle: Text('別のアプリへ移動すると失敗となり、グループの負債と選択アプリの封印が発生します。'),
            ),
          ),
          const SizedBox(height: 16),
          _PreflightCard(deviceSetup: deviceSetup),
          if (command.whenOrNull(error: (error, stackTrace) => error)
              case final error?) ...[
            const SizedBox(height: 16),
            Text(
              taskFailureMessage(error),
              key: const Key('task-command-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('task-start-button'),
            onPressed:
                command.isLoading ||
                    authUser == null ||
                    profile?.groupId == null ||
                    !isReadyToStart
                ? null
                : () =>
                      _start(ownerUid: authUser.id, groupId: profile!.groupId!),
            icon: command.isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('約束を開始'),
          ),
        ],
      ),
    );
  }

  Future<void> _start({
    required String ownerUid,
    required String groupId,
  }) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final content = _contentController.text;
    final succeeded = await ref
        .read(taskCommandControllerProvider.notifier)
        .start(
          ownerUid: ownerUid,
          groupId: groupId,
          content: content,
          durationSeconds: _durationMinutes * 60,
        );
    if (succeeded && mounted) {
      context.go('/task/running');
    }
  }
}

final class _PreflightCard extends StatelessWidget {
  const _PreflightCard({required this.deviceSetup});

  final AsyncValue<DeviceSetupState> deviceSetup;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: deviceSetup.when(
          loading: () => const Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('端末状態を確認中…'),
            ],
          ),
          error: (error, stackTrace) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('端末状態を確認できませんでした。'),
              TextButton(
                onPressed: () => context.go('/device-setup'),
                child: const Text('端末セットアップを開く'),
              ),
            ],
          ),
          data: (state) {
            final ready =
                state.capabilities.isManagedDemoReady &&
                state.savedPackageNames.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ready ? Icons.check_circle : Icons.warning_amber,
                      color: ready
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(ready ? '開始準備ができています' : 'セットアップが必要です'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('封印対象アプリ: ${state.savedPackageNames.length}件'),
                if (!ready)
                  TextButton(
                    key: const Key('task-device-setup-button'),
                    onPressed: () => context.go('/device-setup'),
                    child: const Text('端末セットアップを確認'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
