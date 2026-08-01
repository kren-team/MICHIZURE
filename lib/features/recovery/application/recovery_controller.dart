import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/recovery.dart';

final recoveryControllerProvider =
    NotifierProvider<RecoveryController, RecoveryControllerState>(
      RecoveryController.new,
    );

final class RecoveryControllerState {
  const RecoveryControllerState({
    required this.phase,
    required this.trigger,
    this.report,
  });

  const RecoveryControllerState.idle()
    : phase = RecoveryPhase.idle,
      trigger = null,
      report = null;

  final RecoveryPhase phase;
  final RecoveryTrigger? trigger;
  final RecoveryReport? report;

  bool get isRecovering => switch (phase) {
    RecoveryPhase.checkingLocal ||
    RecoveryPhase.enforcingLocks ||
    RecoveryPhase.restoringAuth ||
    RecoveryPhase.flushingNativeEvent ||
    RecoveryPhase.reconcilingRemote ||
    RecoveryPhase.flushingContributionOutbox => true,
    _ => false,
  };
}

final class RecoveryController extends Notifier<RecoveryControllerState> {
  @override
  RecoveryControllerState build() {
    ref.listen(authStateProvider, (previous, next) {
      final previousId = previous?.value?.id;
      final nextId = next.value?.id;
      if (next.hasValue && previousId != nextId) {
        unawaited(recover(RecoveryTrigger.authRestored));
      }
    });
    ref.listen(currentProfileProvider, (previous, next) {
      if (previous?.hasError == true && next.hasValue) {
        unawaited(recover(RecoveryTrigger.listenerReconnected));
      }
    });
    Future<void>.microtask(() => recover(RecoveryTrigger.coldStart));
    return const RecoveryControllerState.idle();
  }

  Future<RecoveryReport> recover(RecoveryTrigger trigger) async {
    try {
      final report = await ref
          .read(recoveryCoordinatorProvider)
          .run(
            trigger,
            onPhase: (phase) {
              if (ref.mounted) {
                state = RecoveryControllerState(
                  phase: phase,
                  trigger: trigger,
                  report: state.report,
                );
              }
            },
          );
      if (ref.mounted) {
        state = RecoveryControllerState(
          phase: report.terminalPhase,
          trigger: trigger,
          report: report,
        );
      }
      return report;
    } on Object {
      final now = ref.read(clockProvider).now().toUtc();
      final report = RecoveryReport(
        trigger: trigger,
        startedAt: now,
        completedAt: now,
        issues: const [
          RecoveryIssue(RecoveryIssueKind.unknown, RecoveryIssueSeverity.fatal),
        ],
        actions: const {},
        readCountEstimate: 0,
        writeCountEstimate: 0,
      );
      if (ref.mounted) {
        state = RecoveryControllerState(
          phase: RecoveryPhase.failed,
          trigger: trigger,
          report: report,
        );
      }
      return report;
    }
  }
}
