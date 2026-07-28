enum TaskFailureKind {
  invalidContent,
  invalidDuration,
  notAuthenticated,
  groupRequired,
  deviceNotReady,
  noLockTargets,
  alreadyActive,
  noActiveTask,
  notRunning,
  deadlineNotReached,
  conflict,
  offline,
  rulesDenied,
  invalidData,
  unknown,
}

final class TaskFailure implements Exception {
  const TaskFailure(this.kind);

  final TaskFailureKind kind;

  @override
  String toString() => 'TaskFailure($kind)';
}
