import 'dart:async';

import 'package:michizure/features/enforcement/domain/app_lock.dart';
import 'package:michizure/features/enforcement/domain/app_lock_repository.dart';

final class FakeAppLockRepository implements AppLockRepository {
  AppLockState state = emptyAppLockState;
  Object? error;
  Object? releaseError;
  int applyCalls = 0;
  int getCalls = 0;
  int reconcileCalls = 0;
  int releaseCalls = 0;
  LockObligationRequest? lastRequest;
  Completer<AppLockState>? reconcileCompleter;
  String? lastReleasedDebtId;
  LockRemoteStatus? lastResolution;

  @override
  Future<AppLockState> applyObligation(LockObligationRequest request) async {
    applyCalls += 1;
    lastRequest = request;
    if (error case final value?) {
      throw value;
    }
    return state;
  }

  @override
  Future<AppLockState> getState() async {
    getCalls += 1;
    if (error case final value?) {
      throw value;
    }
    return state;
  }

  @override
  Future<AppLockState> reconcile() async {
    reconcileCalls += 1;
    if (error case final value?) {
      throw value;
    }
    if (reconcileCompleter case final completer?) {
      return completer.future;
    }
    return state;
  }

  @override
  Future<AppLockState> releaseObligation({
    required String debtId,
    required LockRemoteStatus resolution,
  }) async {
    releaseCalls += 1;
    lastReleasedDebtId = debtId;
    lastResolution = resolution;
    if (releaseError case final value?) {
      throw value;
    }
    if (error case final value?) {
      throw value;
    }
    return state;
  }
}

const emptyAppLockState = AppLockState(
  obligations: [],
  effectiveTargetCount: 0,
  ownedSuspensionCount: 0,
  appliedCount: 0,
  releasedCount: 0,
  failedCount: 0,
  nextDeadline: null,
);
