import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/recovery_controller.dart';
import '../domain/recovery.dart';

final class RecoveryStatusOverlay extends ConsumerWidget {
  const RecoveryStatusOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recoveryControllerProvider);
    return Stack(
      children: [
        child,
        if (state.isRecovering)
          const Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: LinearProgressIndicator(
                key: Key('recovery-progress-indicator'),
              ),
            ),
          )
        else if (state.phase == RecoveryPhase.degraded ||
            state.phase == RecoveryPhase.actionRequired ||
            state.phase == RecoveryPhase.failed)
          Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Card(
                key: const Key('recovery-status-card'),
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.phase == RecoveryPhase.degraded
                            ? Icons.cloud_off
                            : Icons.sync_problem,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(_message(state.phase))),
                      TextButton(
                        key: const Key('recovery-retry-button'),
                        onPressed: () => ref
                            .read(recoveryControllerProvider.notifier)
                            .recover(RecoveryTrigger.manualRetry),
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _message(RecoveryPhase phase) {
  return switch (phase) {
    RecoveryPhase.degraded => '一部の同期を保留しています。通信状態を確認してください。',
    RecoveryPhase.actionRequired => '端末またはアカウント状態の確認が必要です。',
    RecoveryPhase.failed => '状態を安全に復旧できませんでした。',
    _ => '',
  };
}
