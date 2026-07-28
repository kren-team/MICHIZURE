import 'dart:async';

import 'package:michizure/features/task/domain/native_task_guard.dart';
import 'package:michizure/features/task/domain/task_session.dart';

final class FakeNativeTaskGuard implements NativeTaskGuard {
  final StreamController<NativeTaskEvent> _events =
      StreamController<NativeTaskEvent>.broadcast();

  Object? startError;
  Object? acknowledgeError;
  Object? stopError;
  int startCalls = 0;
  int stopCalls = 0;
  int stateCalls = 0;
  int acknowledgeCalls = 0;
  String? activeTaskId;
  final List<String> acknowledgedEventIds = [];

  void emit(NativeTaskEvent event) => _events.add(event);

  void emitError(Object error) => _events.addError(error);

  Future<void> close() => _events.close();

  @override
  Future<bool> acknowledge(String eventId) async {
    acknowledgeCalls += 1;
    if (acknowledgeError case final error?) {
      throw error;
    }
    acknowledgedEventIds.add(eventId);
    activeTaskId = null;
    return true;
  }

  @override
  Future<NativeTaskGuardState> getState() async {
    stateCalls += 1;
    return NativeTaskGuardState(
      taskSessionId: activeTaskId,
      isRunning: activeTaskId != null,
      hasPendingEvent: false,
    );
  }

  @override
  Future<NativeTaskGuardState> start(TaskSession task) async {
    startCalls += 1;
    if (startError case final error?) {
      throw error;
    }
    activeTaskId = task.id;
    return NativeTaskGuardState(
      taskSessionId: task.id,
      isRunning: true,
      hasPendingEvent: false,
    );
  }

  @override
  Future<void> stop(String taskSessionId) async {
    stopCalls += 1;
    if (stopError case final error?) {
      throw error;
    }
    if (activeTaskId == taskSessionId) {
      activeTaskId = null;
    }
  }

  @override
  Stream<NativeTaskEvent> watchEvents() => _events.stream;
}
