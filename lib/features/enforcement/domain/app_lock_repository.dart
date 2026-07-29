import 'app_lock.dart';

abstract interface class AppLockRepository {
  Future<AppLockState> applyObligation(LockObligationRequest request);

  Future<AppLockState> getState();

  Future<AppLockState> reconcile();

  Future<AppLockState> releaseObligation({
    required String debtId,
    required LockRemoteStatus resolution,
  });
}
