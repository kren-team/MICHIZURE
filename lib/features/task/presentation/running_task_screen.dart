import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/presentation/app_components.dart';
import '../../../core/presentation/app_theme.dart';
import '../../debt/domain/debt.dart';
import '../application/handle_native_task_event.dart';
import '../application/task_command_controller.dart';
import '../domain/task_failure.dart';
import '../domain/task_session.dart';
import 'task_failure_message.dart';

final class RunningTaskScreen extends ConsumerStatefulWidget {
  const RunningTaskScreen({super.key});

  @override
  ConsumerState<RunningTaskScreen> createState() => _RunningTaskScreenState();
}

final class _RunningTaskScreenState extends ConsumerState<RunningTaskScreen> {
  Timer? _ticker;
  String? _guardStartedTaskId;
  String? _navigatedDebtId;

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
    final guard = ref.watch(taskGuardControllerProvider);
    final terminalTask = command.value?.task.isTerminal ?? false
        ? command.value?.task
        : guard.task?.isTerminal ?? false
        ? guard.task
        : null;
    final createdDebt = command.value?.debt ?? guard.debt;

    if (terminalTask != null) {
      return _TaskResultView(
        task: terminalTask,
        debtReps: createdDebt?.totalReps,
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
        if (_guardStartedTaskId != task.id) {
          _guardStartedTaskId = task.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref
                  .read(taskGuardControllerProvider.notifier)
                  .ensureStarted(task);
            }
          });
        }
        return _RunningTaskView(
          task: task,
          remaining: remaining,
          command: command,
          guard: guard,
          onAbort: () => _confirmAbort(task),
          onRetryGuard: () =>
              ref.read(taskGuardControllerProvider.notifier).retry(),
        );
      },
    );
  }

  Future<void> _confirmAbort(TaskSession task) async {
    final shouldAbort = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('約束を中断しますか？'),
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
      final completed = await ref
          .read(taskCommandControllerProvider.notifier)
          .abort(ownerUid: task.ownerUid, taskId: task.id);
      if (!completed || !mounted) {
        return;
      }
      final debt = ref.read(taskCommandControllerProvider).value?.debt;
      if (debt != null) {
        _openCreatedDebt(debt);
      }
    }
  }

  void _openCreatedDebt(Debt debt) {
    if (_navigatedDebtId == debt.id) {
      return;
    }
    _navigatedDebtId = debt.id;
    ref.invalidate(activeGroupDebtsProvider);
    ref.invalidate(debtProvider(debt.id));
    ref.invalidate(debtContributionsProvider(debt.id));
    context.go('/debts/${debt.id}', extra: debt);
  }
}

final class _RunningTaskView extends StatelessWidget {
  const _RunningTaskView({
    required this.task,
    required this.remaining,
    required this.command,
    required this.guard,
    required this.onAbort,
    required this.onRetryGuard,
  });

  final TaskSession task;
  final Duration remaining;
  final AsyncValue<TaskCommandResult?> command;
  final TaskGuardControllerState guard;
  final VoidCallback onAbort;
  final VoidCallback onRetryGuard;

  @override
  Widget build(BuildContext context) {
    final error = command.whenOrNull(error: (error, stackTrace) => error);
    return Scaffold(
      appBar: AppBar(title: const Text('約束を実行中')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MichizureSpacing.page),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
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
                  MichizureMetricCard(
                    label: '残り時間',
                    value: _formatRemaining(remaining),
                    valueKey: const Key('running-task-countdown'),
                    icon: Icons.timer_outlined,
                    description: '終了予定時刻から残り時間を計算しています',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '別のアプリへ移動すると、この約束は失敗になります。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            guard.phase == TaskGuardPhase.monitoring
                                ? Icons.shield
                                : guard.phase == TaskGuardPhase.retryNeeded
                                ? Icons.warning_amber
                                : Icons.sync,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _guardStatusMessage(guard.phase, remaining),
                              key: const Key('task-guard-status'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (guard.phase == TaskGuardPhase.retryNeeded) ...[
                    const SizedBox(height: 12),
                    Text(
                      _guardFailureMessage(guard.failure),
                      key: const Key('task-guard-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    MichizurePrimaryButton(
                      buttonKey: const Key('task-guard-retry-button'),
                      onPressed: onRetryGuard,
                      child: const Text('監視・同期を再試行'),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      taskFailureMessage(error),
                      key: const Key('running-task-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
      ),
    );
  }
}

String _guardStatusMessage(TaskGuardPhase phase, Duration remaining) {
  return switch (phase) {
    TaskGuardPhase.idle || TaskGuardPhase.starting => '約束の監視を開始しています',
    TaskGuardPhase.monitoring when remaining == Duration.zero =>
      '端末内のdeadline判定を確定しています',
    TaskGuardPhase.monitoring => '端末内で外部アプリへの移動を監視中です',
    TaskGuardPhase.synchronizing => '約束の結果を安全に同期しています',
    TaskGuardPhase.retryNeeded => '監視または結果同期に再試行が必要です',
    TaskGuardPhase.terminal => '約束の結果を確定しました',
  };
}

String _guardFailureMessage(Object? error) {
  if (error is TaskFailure) {
    return taskFailureMessage(error);
  }
  if (error == null) {
    return '端末のTask監視状態を確認できません。再試行してください。';
  }
  return '端末のTask監視を継続できません。権限と通信状態を確認して再試行してください。';
}

final class _TaskResultView extends StatelessWidget {
  const _TaskResultView({required this.task, this.debtReps});

  final TaskSession task;
  final int? debtReps;

  @override
  Widget build(BuildContext context) {
    final succeeded = task.status == TaskSessionStatus.succeeded;
    return Scaffold(
      appBar: AppBar(title: Text(succeeded ? '約束達成' : '約束失敗')),
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
                succeeded ? '約束を達成しました' : '約束は失敗として記録されました',
                key: Key(
                  succeeded ? 'task-success-title' : 'task-failed-title',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (!succeeded && debtReps != null) ...[
                const SizedBox(height: 8),
                Text('発生した負債: $debtReps回'),
                const SizedBox(height: 8),
                const Text('グループのメンバーがスクワットで一緒に返済できます。'),
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
            Text(noActiveTask ? '実行中の約束はありません。' : '約束を復元できませんでした。'),
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
