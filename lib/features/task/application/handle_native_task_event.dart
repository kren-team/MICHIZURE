import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../debt/domain/debt.dart';
import '../../enforcement/domain/app_lock.dart';
import '../domain/native_task_guard.dart';
import '../domain/task_failure.dart';
import '../domain/task_session.dart';

enum TaskGuardPhase {
  idle,
  starting,
  monitoring,
  synchronizing,
  retryNeeded,
  terminal,
}

final class TaskGuardControllerState {
  const TaskGuardControllerState({
    required this.phase,
    this.task,
    this.debt,
    this.failure,
    this.lockState,
  });

  const TaskGuardControllerState.idle()
    : phase = TaskGuardPhase.idle,
      task = null,
      debt = null,
      failure = null,
      lockState = null;

  final TaskGuardPhase phase;
  final TaskSession? task;
  final Debt? debt;
  final Object? failure;
  final AppLockState? lockState;
}

final taskGuardControllerProvider =
    NotifierProvider<TaskGuardController, TaskGuardControllerState>(
      TaskGuardController.new,
    );

final class TaskGuardController extends Notifier<TaskGuardControllerState> {
  StreamSubscription<NativeTaskEvent>? _subscription;
  TaskSession? _task;
  NativeTaskEvent? _pendingEvent;
  final Set<String> _handledEventIds = {};
  final Set<String> _inFlightEventIds = {};
  bool _startInFlight = false;
  Timer? _retryTimer;

  @override
  TaskGuardControllerState build() {
    _subscription = ref
        .read(nativeTaskGuardProvider)
        .watchEvents()
        .listen(_receive, onError: _receiveStreamError);
    ref.onDispose(() {
      _retryTimer?.cancel();
      unawaited(_subscription?.cancel());
    });
    return const TaskGuardControllerState.idle();
  }

  Future<void> ensureStarted(TaskSession task) async {
    _task = task;
    if (task.isTerminal) {
      state = TaskGuardControllerState(
        phase: TaskGuardPhase.terminal,
        task: task,
      );
      await _requestPendingReplay();
      return;
    }
    if (_startInFlight) {
      return;
    }
    _startInFlight = true;
    state = TaskGuardControllerState(
      phase: TaskGuardPhase.starting,
      task: task,
    );
    try {
      final nativeState = await ref.read(nativeTaskGuardProvider).start(task);
      if (nativeState.taskSessionId != task.id || !nativeState.isRunning) {
        throw const NativeTaskGuardFailure(
          NativeTaskGuardFailureKind.invalidData,
        );
      }
      if (ref.mounted && _pendingEvent == null) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.monitoring,
          task: task,
        );
      }
      await _requestPendingReplay();
    } on Object catch (error) {
      if (ref.mounted) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.retryNeeded,
          task: task,
          failure: _safeGuardFailure(error),
        );
      }
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> retry() async {
    final event = _pendingEvent;
    if (event != null) {
      await _handle(event);
      return;
    }
    final task = _task;
    if (task != null) {
      await ensureStarted(task);
    }
  }

  Future<void> stop(String taskSessionId) async {
    _retryTimer?.cancel();
    await ref.read(nativeTaskGuardProvider).stop(taskSessionId);
    if (ref.mounted) {
      state = const TaskGuardControllerState.idle();
    }
  }

  void _receive(NativeTaskEvent event) {
    unawaited(_handle(event));
  }

  void _receiveStreamError(Object error, StackTrace stackTrace) {
    final task = _task;
    if (ref.mounted) {
      state = TaskGuardControllerState(
        phase: TaskGuardPhase.retryNeeded,
        task: task,
        failure: _safeGuardFailure(error),
      );
    }
  }

  Future<void> _handle(NativeTaskEvent event) async {
    if (_handledEventIds.contains(event.eventId) ||
        !_inFlightEventIds.add(event.eventId)) {
      return;
    }
    _pendingEvent = event;
    var task = _task;
    if (task == null) {
      try {
        task = await ref
            .read(taskRepositoryProvider)
            .watchTask(event.taskSessionId)
            .first;
        _task = task;
      } on Object catch (error) {
        _inFlightEventIds.remove(event.eventId);
        if (ref.mounted) {
          state = TaskGuardControllerState(
            phase: TaskGuardPhase.retryNeeded,
            failure: error is TaskFailure ? error : _safeGuardFailure(error),
          );
        }
        _scheduleRetry();
        return;
      }
    }
    if (task == null || task.id != event.taskSessionId) {
      _inFlightEventIds.remove(event.eventId);
      if (ref.mounted) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.retryNeeded,
          task: task,
          failure: const NativeTaskGuardFailure(
            NativeTaskGuardFailureKind.invalidData,
          ),
        );
      }
      return;
    }
    if (ref.mounted) {
      state = TaskGuardControllerState(
        phase: TaskGuardPhase.synchronizing,
        task: task,
      );
    }

    try {
      TaskSession terminalTask;
      Debt? debt;
      AppLockState? lockState;
      if (task.isTerminal &&
          !(task.status == TaskSessionStatus.failed &&
              task.failureEventId == event.eventId)) {
        terminalTask = task;
      } else if (event.type == NativeTaskEventType.deadlineReached) {
        terminalTask = await ref
            .read(taskRepositoryProvider)
            .succeedTask(ownerUid: task.ownerUid, taskId: task.id);
      } else {
        final reason = event.failureReason;
        if (reason == null) {
          throw const NativeTaskGuardFailure(
            NativeTaskGuardFailureKind.invalidData,
          );
        }
        final result = await ref
            .read(taskRepositoryProvider)
            .failTaskAndCreateDebt(
              ownerUid: task.ownerUid,
              taskId: task.id,
              reason: reason,
              failureEventId: event.eventId,
            );
        terminalTask = result.task;
        debt = result.debt;
        lockState = await ref
            .read(appLockRepositoryProvider)
            .applyObligation(
              LockObligationRequest(
                debtId: result.debt.id,
                taskSessionId: result.task.id,
                createdAt: result.debt.createdAt,
                expiresAt: result.debt.lockExpiresAt,
              ),
            );
      }

      final acknowledged = await ref
          .read(nativeTaskGuardProvider)
          .acknowledge(event.eventId);
      if (!acknowledged) {
        throw const NativeTaskGuardFailure(
          NativeTaskGuardFailureKind.nativeStateCorrupt,
        );
      }
      _handledEventIds.add(event.eventId);
      _pendingEvent = null;
      _retryTimer?.cancel();
      if (ref.mounted) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.terminal,
          task: terminalTask,
          debt: debt,
          lockState: lockState,
        );
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.retryNeeded,
          task: task,
          failure: error is TaskFailure ? error : _safeGuardFailure(error),
        );
      }
      _scheduleRetry();
    } finally {
      _inFlightEventIds.remove(event.eventId);
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      if (ref.mounted && _pendingEvent != null) {
        unawaited(retry());
      }
    });
  }

  Future<void> _requestPendingReplay() async {
    try {
      await ref.read(nativeTaskGuardProvider).getState();
    } on Object catch (error) {
      if (ref.mounted && _pendingEvent == null) {
        state = TaskGuardControllerState(
          phase: TaskGuardPhase.retryNeeded,
          task: _task,
          failure: _safeGuardFailure(error),
        );
      }
    }
  }
}

NativeTaskGuardFailure _safeGuardFailure(Object error) {
  return error is NativeTaskGuardFailure
      ? error
      : const NativeTaskGuardFailure(NativeTaskGuardFailureKind.unknown);
}
