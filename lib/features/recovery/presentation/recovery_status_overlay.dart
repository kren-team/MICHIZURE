import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/app_theme.dart';
import '../application/recovery_controller.dart';
import '../domain/recovery.dart';

final class RecoveryStatusOverlay extends ConsumerStatefulWidget {
  const RecoveryStatusOverlay({required this.child, this.onRetry, super.key});

  final Widget child;
  final VoidCallback? onRetry;

  @override
  ConsumerState<RecoveryStatusOverlay> createState() =>
      _RecoveryStatusOverlayState();
}

final class _RecoveryStatusOverlayState
    extends ConsumerState<RecoveryStatusOverlay> {
  String? _dismissedWarning;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recoveryControllerProvider);
    final warning = _warningKey(state.phase);
    return Column(
      children: [
        if (state.isRecovering)
          const SafeArea(
            bottom: false,
            child: LinearProgressIndicator(
              key: Key('recovery-progress-indicator'),
            ),
          )
        else if (warning != null && warning != _dismissedWarning)
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Card(
                  key: const Key('recovery-status-card'),
                  color: MichizureColors.elevatedSurface,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
                    child: Row(
                      children: [
                        Icon(
                          state.phase == RecoveryPhase.degraded
                              ? Icons.cloud_off_outlined
                              : Icons.sync_problem,
                          color: MichizureColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _message(state.phase),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          key: const Key('recovery-retry-button'),
                          onPressed:
                              widget.onRetry ??
                              () => ref
                                  .read(recoveryControllerProvider.notifier)
                                  .recover(RecoveryTrigger.manualRetry),
                          child: const Text('再試行'),
                        ),
                        IconButton(
                          key: const Key('recovery-close-button'),
                          tooltip: '閉じる',
                          onPressed: () => setState(() {
                            _dismissedWarning = warning;
                          }),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}

String? _warningKey(RecoveryPhase phase) => switch (phase) {
  RecoveryPhase.degraded ||
  RecoveryPhase.actionRequired ||
  RecoveryPhase.failed => '${phase.name}:${_message(phase)}',
  _ => null,
};

String _message(RecoveryPhase phase) {
  return switch (phase) {
    RecoveryPhase.degraded => '一部の同期を保留しています。通信状態を確認してください。',
    RecoveryPhase.actionRequired => '端末またはアカウント状態の確認が必要です。',
    RecoveryPhase.failed => '状態を安全に復旧できませんでした。',
    _ => '',
  };
}
