import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../application/task_command_controller.dart';
import '../domain/task_session.dart';
import 'task_failure_message.dart';

final class RunningTaskScreen extends ConsumerStatefulWidget {
  const RunningTaskScreen({super.key});

  @override
  ConsumerState<RunningTaskScreen> createState() => _RunningTaskScreenState();
}

final class _RunningTaskScreenState extends ConsumerState<RunningTaskScreen> {
  Timer? _ticker;
  String? _completionAttemptedTaskId;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTask = ref.watch(activeTaskSessionProvider);
    final command = ref.watch(taskCommandControllerProvider);
    final terminalTask = command.value?.task.isTerminal ?? false
        ? command.value?.task
        : null;

    if (terminalTask != null) {
      return _TaskResultView(
        task: terminalTask,
        debtReps: command.value?.debt?.totalReps,
      );
    }

    return activeTask.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => _TaskLoadError(
        onRetry: () => ref.invalidate(activeTaskSessionProvider),
      ),
      data: (task) {
        if (task == null) {
          return const _TaskLoadError(noActiveTask: true);
        }
        if (task.isTerminal) {
          return _TaskResultView(task: task);
        }
        final now = ref.read(clockProvider).now().toUtc();
        final remaining = task.remainingAt(now);
        if (remaining == Duration.zero &&
            _completionAttemptedTaskId != task.id &&
            !command.isLoading) {
          _completionAttemptedTaskId = task.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _complete(task);
            }
          });
        }
        return _RunningTaskView(
          task: task,
          remaining: remaining,
          command: command,
          onAbort: () => _confirmAbort(task),
          onRetryCompletion: remaining == Duration.zero
              ? () {
                  _completionAttemptedTaskId = null;
                  _complete(task);
                }
              : null,
        );
      },
    );
  }

  Future<void> _complete(TaskSession task) async {
    await ref
        .read(taskCommandControllerProvider.notifier)
        .succeed(ownerUid: task.ownerUid, taskId: task.id);
  }

  Future<void> _confirmAbort(TaskSession task) async {
    final shouldAbort = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Taskを中断しますか？'),
        content: const Text('中断は失敗として記録され、グループにスクワット負債が発生します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('続ける'),
          ),
          FilledButton(
            key: const Key('task-abort-confirm-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('失敗として中断'),
          ),
        ],
      ),
    );
    if (shouldAbort ?? false) {
      await ref
          .read(taskCommandControllerProvider.notifier)
          .abort(ownerUid: task.ownerUid, taskId: task.id);
    }
  }
}

final class _RunningTaskView extends StatelessWidget {
  const _RunningTaskView({
    required this.task,
    required this.remaining,
    required this.command,
    required this.onAbort,
    required this.onRetryCompletion,
  });

  final TaskSession task;
  final Duration remaining;
  final AsyncValue<TaskCommandResult?> command;
  final VoidCallback onAbort;
  final VoidCallback? onRetryCompletion;

  @override
  Widget build(BuildContext context) {
    final error = command.whenOrNull(error: (error, stackTrace) => error);
    return Scaffold(
      appBar: AppBar(title: const Text('Task実行中')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  task.content,
                  key: const Key('running-task-content'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Text(
                  _formatRemaining(remaining),
                  key: const Key('running-task-countdown'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                const Text('終了時刻から残り時間を再計算しています', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('外部アプリの自動検知はまだ有効ではありません。Task中はこの画面を維持してください。'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    taskFailureMessage(error),
                    key: const Key('running-task-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (onRetryCompletion != null)
                    FilledButton(
                      key: const Key('task-success-retry-button'),
                      onPressed: command.isLoading ? null : onRetryCompletion,
                      child: const Text('完了処理を再試行'),
                    ),
                ],
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const Key('task-abort-button'),
                  onPressed: command.isLoading ? null : onAbort,
                  child: const Text('失敗として中断'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _TaskResultView extends StatelessWidget {
  const _TaskResultView({required this.task, this.debtReps});

  final TaskSession task;
  final int? debtReps;

  @override
  Widget build(BuildContext context) {
    final succeeded = task.status == TaskSessionStatus.succeeded;
    return Scaffold(
      appBar: AppBar(title: Text(succeeded ? 'Task完了' : 'Task失敗')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                succeeded ? Icons.check_circle : Icons.error,
                size: 72,
                color: succeeded
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                succeeded ? '約束を達成しました' : 'Taskは失敗として記録されました',
                key: Key(
                  succeeded ? 'task-success-title' : 'task-failed-title',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (!succeeded && debtReps != null) ...[
                const SizedBox(height: 8),
                Text('発生した負債: $debtReps回'),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('task-result-home-button'),
                onPressed: () => context.go('/home'),
                child: const Text('ホームへ戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TaskLoadError extends StatelessWidget {
  const _TaskLoadError({this.onRetry, this.noActiveTask = false});

  final VoidCallback? onRetry;
  final bool noActiveTask;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(noActiveTask ? '実行中のTaskはありません。' : 'Taskを復元できませんでした。'),
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('再試行')),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('ホームへ戻る'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRemaining(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return [
    hours.toString().padLeft(2, '0'),
    minutes.toString().padLeft(2, '0'),
    seconds.toString().padLeft(2, '0'),
  ].join(':');
}
